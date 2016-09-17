{-# LANGUAGE GeneralizedNewtypeDeriving #-}
-- | Screen frames.
module Game.LambdaHack.Client.UI.Frame
  ( SingleFrame(..), Frames, overlayFrame, overlayFrameWithLines
  ) where

import Prelude ()

import Game.LambdaHack.Common.Prelude

import qualified Data.EnumMap.Strict as EM
import Data.Word (Word32)

import Game.LambdaHack.Client.UI.Overlay
import Game.LambdaHack.Common.Color
import Game.LambdaHack.Common.Misc
import Game.LambdaHack.Common.Point
import qualified Game.LambdaHack.Common.PointArray as PointArray

-- | An overlay that fits on the screen (or is meant to be truncated on display)
-- and is padded to fill the whole screen
-- and is displayed as a single game screen frame.
newtype SingleFrame = SingleFrame
  {singleFrame :: PointArray.GArray Word32 AttrCharW32}
  deriving (Eq, Show)

-- | Sequences of screen frames, including delays.
type Frames = [Maybe SingleFrame]

-- | Truncate the overlay: for each line, if it's too long, it's truncated
-- and if there are too many lines, excess is dropped and warning is appended.
truncateLines :: Bool -> [AttrLine] -> [AttrLine]
truncateLines onBlank l =
  let lxsize = fst normalLevelBound + 1  -- TODO
      lysize = snd normalLevelBound + 1
      canvasLength = if onBlank then lysize + 3 else lysize + 1
      topLayer = if length l <= canvasLength
                 then l ++ if length l < canvasLength
                           then [[]]
                           else []
                 else take (canvasLength - 1) l
                      ++ [stringToAL "--a portion of the text trimmed--"]
      f lenPrev lenNext layerLine =
        truncateAttrLine lxsize layerLine (max lenPrev lenNext)
      lens = map (\al -> min (lxsize - 1) (length al)) topLayer
  in zipWith3 f (0 : lens) (drop 1 lens ++ [0]) topLayer

-- | Add a space at the message end, for display overlayed over the level map.
-- Also trim (do not wrap!) too long lines.
truncateAttrLine :: X -> AttrLine -> X -> AttrLine
truncateAttrLine w xs lenMax =
  case compare w (length xs) of
    LT -> let discarded = drop w xs
          in if all (== spaceAttrW32) discarded
             then take w xs
             else take (w - 1) xs
                  ++ [attrCharToW32 $ AttrChar (Attr BrBlack defBG) '$']
    EQ -> xs
    GT -> let xsSpace = if null xs || last xs == spaceAttrW32
                        then xs
                        else xs ++ [spaceAttrW32]
              whiteN = max (40 - length xsSpace) (1 + lenMax - length xsSpace)
          in xsSpace ++ replicate whiteN spaceAttrW32

linesToOverlay :: [AttrLine] -> Overlay
linesToOverlay al =
  let fLine y = zipWith (\x ac -> (Point x y, ac)) [0..]
  in EM.fromList $ concat $ zipWith fLine [0..] al

-- | Overlays either the game map only or the whole empty screen frame.
-- We assume the lines of the overlay are not too long nor too many.
overlayFrame :: Overlay -> Maybe SingleFrame -> SingleFrame
overlayFrame ov msf =
  let lxsize = fst normalLevelBound + 1  -- TODO
      lysize = snd normalLevelBound + 1
      canvasLength = if isNothing msf then lysize + 3 else lysize + 1
      canvas = case msf of
        Nothing -> PointArray.replicateA lxsize canvasLength spaceAttrW32
        Just SingleFrame{..} -> singleFrame
  in SingleFrame $ canvas PointArray.// EM.assocs ov

overlayFrameWithLines :: [AttrLine] -> Maybe SingleFrame -> SingleFrame
overlayFrameWithLines l msf =
  let ov = linesToOverlay $ truncateLines  (isNothing msf) l
  in overlayFrame ov msf
