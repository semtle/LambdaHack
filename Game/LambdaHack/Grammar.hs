module Game.LambdaHack.Grammar where

import Data.Char
import qualified Data.Set as S
import qualified Data.List as L
import Data.Maybe

import Game.LambdaHack.Item
import Game.LambdaHack.Actor
import Game.LambdaHack.State
import Game.LambdaHack.Content.ItemKind
import Game.LambdaHack.Content.ActorKind
import Game.LambdaHack.Effect
import Game.LambdaHack.Flavour
import qualified Game.LambdaHack.Kind as Kind

type Verb = String
type Object = String

vowel :: Char -> Bool
vowel l = l `elem` "aeio"  -- TODO: 'u' is hard, as is "eu"

suffixS :: String -> String
suffixS word = case L.reverse word of
                'h' : 'c' : _ -> word ++ "es"
                'h' : 's' : _ -> word ++ "es"
                'i' : 's' : _ -> word ++ "es"
                's' : _ -> word ++ "es"
                'z' : _ -> word ++ "es"
                'x' : _ -> word ++ "es"
                'g' : _ -> word ++ "es"
                'j' : _ -> word ++ "es"
                'y' : l : _ | not (vowel l) -> init word ++ "ies"
                _ -> word ++ "s"

capitalize :: String -> String
capitalize [] = []
capitalize (c : cs) = toUpper c : cs

addIndefinite :: String -> String
addIndefinite b = case b of
                    c : _ | vowel c -> "an " ++ b  -- TODO: 'h' is hard
                    _               -> "a "  ++ b

makeObject :: Int -> (Object -> Object) -> Object -> String
makeObject 1 adj obj = addIndefinite $ adj obj
makeObject n adj obj = show n ++ " " ++ adj (suffixS obj)

-- TODO: when there's more of the above, split and move to Utils/

-- | How to refer to an actor in object position of a sentence.
objectActor :: Kind.Ops ActorKind -> Actor -> String
objectActor Kind.Ops{oname} a =
  fromMaybe (oname $ bkind a) (bname a)

-- | How to refer to an actor in subject position of a sentence.
subjectActor :: Kind.Ops ActorKind -> Actor -> String
subjectActor cops x = capitalize $ objectActor cops x

verbActor :: Kind.Ops ActorKind -> Actor -> Verb -> String
verbActor cops a v = if objectActor cops a == "you" then v else suffixS v

-- | Sentences such like "The dog barks".
subjectActorVerb :: Kind.Ops ActorKind -> Actor -> Verb -> String
subjectActorVerb cops x v = subjectActor cops x ++ " " ++ verbActor cops x v

compoundVerbActor :: Kind.Ops ActorKind -> Actor -> Verb -> String -> String
compoundVerbActor cops m v p = verbActor cops m v ++ " " ++ p

subjectVerbIObject :: Kind.COps -> State -> Actor -> Verb -> Item -> String
                   -> String
subjectVerbIObject Kind.COps{coactor, coitem} state m v o add =
  subjectActor coactor m ++ " " ++
  verbActor coactor m v ++ " " ++
  objectItem coitem state o ++ add ++ "."

subjectVerbMObject :: Kind.Ops ActorKind -> Actor -> Verb -> Actor -> String
                   -> String
subjectVerbMObject cops m v o add =
  subjectActor cops m ++ " " ++
  verbActor cops m v ++ " " ++
  objectActor cops o ++ add ++ "."

subjCompoundVerbIObj :: Kind.COps -> State -> Actor -> Verb -> String
                     -> Item -> String -> String
subjCompoundVerbIObj Kind.COps{coactor, coitem} state m v p o add =
  subjectActor coactor m ++ " " ++
  compoundVerbActor coactor m v p ++ " " ++
  objectItem coitem state o ++ add ++ "."

objectItem :: Kind.Ops ItemKind -> State -> Item -> String
objectItem cops@Kind.Ops{okind} state o =
  let ik = jkind o
      kind = okind ik
      identified = L.length (iflavour kind) == 1 ||
                   ik `S.member` sdisco state
      addSpace s = if s == "" then "" else " " ++ s
      eff = effectToName (ieffect kind)
      pwr = if jpower o == 0 then "" else "(+" ++ show (jpower o) ++ ")"
      adj name = if identified
                 then name ++ addSpace eff ++ addSpace pwr
                 else let flavour = getFlavour cops (sflavour state) ik
                      in flavourToName flavour ++ " " ++ name
  in  makeObject (jcount o) adj (iname kind)
