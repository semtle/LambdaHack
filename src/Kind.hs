module Kind
  (Id, Kind.getKind, getId, getId', frequency, foldWithKey)
  where

import Data.Binary
import qualified Data.List as L
import qualified Data.IntMap as IM
import Control.Monad

import Content
import Frequency

newtype Id a = Id Int
  deriving (Show, Eq, Ord)

instance Binary (Id a) where
  put (Id i) = put i
  get = liftM Id get

getKind :: Content a => Id a -> a
getKind (Id i) = kindMap IM.! i

getId' :: Content a => (a -> Bool) -> [(Id a, a)]
getId' f = [(Id i, k) | (i, k) <- kindAssocs, f k]

getId :: (Content a, Eq a) => a -> Id a
getId a = fst $ head $ getId' (== a)

frequency :: Content a => Frequency (Id a, a)
frequency = Frequency [(getFreq k, (Id i, k)) | (i, k) <- kindAssocs]

foldWithKey :: Content a => (Id a -> a -> b -> b) -> b -> b
foldWithKey f z = L.foldr (\ (k, a) -> f (Id k) a) z kindAssocs
