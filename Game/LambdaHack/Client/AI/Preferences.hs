-- | Actor preferences for targets and actions based on actor attributes.
module Game.LambdaHack.Client.AI.Preferences
  ( totalUsefulness, effectToBenefit
  ) where

import qualified Control.Monad.State as St
import qualified Data.EnumMap.Strict as EM
import Data.Maybe

import Game.LambdaHack.Common.Actor
import Game.LambdaHack.Common.ActorState
import qualified Game.LambdaHack.Common.Dice as Dice
import Game.LambdaHack.Common.Faction
import Game.LambdaHack.Common.Item
import Game.LambdaHack.Common.ItemStrongest
import qualified Game.LambdaHack.Common.Kind as Kind
import Game.LambdaHack.Common.Misc
import Game.LambdaHack.Content.ItemKind (ItemKind)
import qualified Game.LambdaHack.Content.ItemKind as IK
import Game.LambdaHack.Content.ModeKind

-- | How much AI benefits from applying the effect. Multipllied by item p.
-- Negative means harm to the enemy when thrown at him. Effects with zero
-- benefit won't ever be used, neither actively nor passively.
effectToBenefit :: Kind.COps -> Actor -> [ItemFull] -> Faction
                -> IK.Effect Int -> Int
effectToBenefit cops b activeItems fact eff =
  let dungeonDweller = not $ fcanEscape $ gplayer fact
  in case eff of
    IK.NoEffect _ -> 0
    IK.Hurt d -> -(min 99 $ round (10 * Dice.meanDice d))
    IK.Burn p -> -15 * p           -- usually splash damage, etc.
    IK.Explode _ -> -10
    IK.RefillHP p ->
      let hpMax = sumSlotNoFilter IK.EqpSlotAddMaxHP activeItems
      in if p > 0
         then 1 + 10 * min p (fromIntegral $ (xM hpMax - bhp b) `divUp` oneM)
         else max (-99) (10 * p)
    IK.OverfillHP p ->
      let hpMax = sumSlotNoFilter IK.EqpSlotAddMaxHP activeItems
      in if p > 0
         then 2 + 10 * min p (fromIntegral $ (xM hpMax - bhp b) `divUp` oneM)
         else max (-99) (10 * p)
    IK.RefillCalm p ->
      let calmMax = sumSlotNoFilter IK.EqpSlotAddMaxCalm activeItems
      in if p > 0
         then 1 + min p (fromIntegral $ (xM calmMax - bcalm b) `divUp` oneM)
         else max (-20) p
    IK.OverfillCalm p ->
      let calmMax = sumSlotNoFilter IK.EqpSlotAddMaxCalm activeItems
      in if p > 0
         then 2 + min p (fromIntegral $ (xM calmMax - bcalm b) `divUp` oneM)
         else max (-20) p
    IK.Dominate -> -200
    IK.Impress -> -10
    IK.CallFriend p -> 20 * p
    IK.Summon{} | dungeonDweller -> 1 -- probably summons friends or crazies
    IK.Summon{} -> 0                  -- probably generates enemies
    IK.Ascend{} -> 1               -- change levels sensibly, in teams
    IK.Escape{} -> 10000           -- AI wants to win; spawners to guard
    IK.Paralyze p -> -20 * p
    IK.InsertMove p -> 50 * p
    IK.Teleport p | p <= 9 -> 10  -- blink to shoot at foe
    IK.Teleport p | p <= 19 -> 1  -- neither escape nor repositioning
    IK.Teleport p -> -5 * p  -- get rid of the foe
    IK.CreateItem COrgan grp _ ->  -- TODO: use the timeout
      let (total, count) = organBenefit grp cops b
      in total `divUp` count  -- average over all matching grp; rarities ignored
    IK.CreateItem _ _ _ -> 30
    IK.DropItem COrgan grp True ->  -- calculated for future use, general pickup
      let (total, _) = organBenefit grp cops b
      in - total  -- sum over all matching grp; simplification: rarities ignored
    IK.DropItem _ _ False -> -15
    IK.DropItem _ _ True -> -30
    IK.PolyItem _ -> 0  -- AI would loop
    IK.Identify _ -> 0  -- AI would loop
    IK.SendFlying _ -> -10  -- but useful on self sometimes, too
    IK.PushActor _ -> -10  -- but useful on self sometimes, too
    IK.PullActor _ -> -10
    IK.DropBestWeapon -> -50
    IK.ActivateInv ' ' -> -100
    IK.ActivateInv _ -> -50
    IK.ApplyPerfume -> -10
    IK.OneOf _ -> 1  -- usually a mixed blessing, but slightly beneficial
    IK.OnSmash _ -> -10
    IK.Recharging e -> effectToBenefit cops b activeItems fact e
                           `divUp` 3  -- TODO: use Timeout
    IK.Temporary _ -> 0

-- TODO: calculating this for "temporary conditions" takes forever
organBenefit :: GroupName ItemKind -> Kind.COps -> Actor -> (Int, Int)
organBenefit t cops@Kind.COps{coitem=Kind.Ops{ofoldrGroup}} b =
  let travA x = St.evalState (IK.aspectTrav x (return . round . Dice.meanDice)) ()
      f p _ kind (sacc, pacc) =
        let paspect asp = p * aspectToBenefit cops b (travA asp)
        in ( sacc + sum (map paspect $ IK.iaspects kind)
           , pacc + p )
  in ofoldrGroup t f (0, 0)

-- | Return the value to add to effect value.
aspectToBenefit :: Kind.COps -> Actor -> IK.Aspect Int -> Int
aspectToBenefit _cops _b asp =
  case asp of
    IK.Periodic{} -> 0
    IK.Timeout{} -> 0
    IK.AddMaxHP p -> p * 10
    IK.AddMaxCalm p -> p `divUp` 2
    IK.AddSpeed p -> p * 10000
    IK.AddSkills m -> 5 * sum (EM.elems m)
    IK.AddHurtMelee _p -> 1  -- TODO: negative only for weapons; p `divUp` 3
    IK.AddHurtRanged p -> - p `divUp` 5
    IK.AddArmorMelee p -> p `divUp` 5
    IK.AddArmorRanged p -> p `divUp` 10
    IK.AddSight p -> p * 10
    IK.AddSmell p -> p * 2
    IK.AddLight p -> p * 10

-- | Determine the total benefit from having an item in eqp or inv,
-- according to item type, and also the benefit confered by equipping the item
-- and from meleeing with it or applying it or throwing it.
totalUsefulness :: Kind.COps -> Actor -> [ItemFull] -> Faction -> ItemFull
                -> Maybe (Int, (Int, Int))
totalUsefulness cops b activeItems fact itemFull =
  let ben effects aspects =
        let effBens = map (effectToBenefit cops b activeItems fact) effects
            aspBens = map (aspectToBenefit cops b) aspects
            periodicEffBens = map (effectToBenefit cops b activeItems fact)
                                  (allRecharging effects)
            periodicBens =
              case strengthFromEqpSlot IK.EqpSlotPeriodic itemFull of
                Nothing -> []
                Just timeout ->
                  map (\eff -> eff * 10 `divUp` timeout) periodicEffBens
            selfBens = aspBens ++ periodicBens
            eqpSum = if not (null selfBens) && minimum selfBens < -10
                                            && maximum selfBens > 10
                     then 0  -- significant mixed blessings out of AI control
                     else sum selfBens
            effSum = sum effBens
            isWeapon =
              isJust (strengthFromEqpSlot IK.EqpSlotWeapon itemFull)
            totalSum = if goesIntoInv $ itemBase itemFull
                       then effSum
                       else if isWeapon
                            then effSum + eqpSum
                            else eqpSum
        in (totalSum, (eqpSum, effSum))
  in case itemDisco itemFull of
    Just ItemDisco{itemAE=Just ItemAspectEffect{jaspects, jeffects}} ->
      Just $ ben jeffects jaspects
    Just ItemDisco{itemKind=IK.ItemKind{iaspects, IK.ieffects}} ->
      let travA x =
            St.evalState (IK.aspectTrav x (return . round . Dice.meanDice))
                         ()
          jaspects = map travA iaspects
          travE x =
            St.evalState (IK.effectTrav x (return . round . Dice.meanDice))
                         ()
          jeffects = map travE ieffects
      in Just $ ben jeffects jaspects
    _ -> Nothing
