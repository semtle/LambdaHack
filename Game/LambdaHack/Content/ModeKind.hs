-- | The type of kinds of game modes.
module Game.LambdaHack.Content.ModeKind
  ( Caves, Players(..), Player(..), ModeKind(..), validateModeKind
  ) where

import Data.Binary
import qualified Data.EnumMap.Strict as EM
import Data.Text (Text)
import qualified NLP.Miniutter.English as MU ()

import Game.LambdaHack.Common.Misc (Freqs)

-- | Game mode specification.
data ModeKind = ModeKind
  { msymbol  :: !Char     -- ^ a symbol (matches the keypress, if any)
  , mname    :: !Text     -- ^ short description
  , mfreq    :: !Freqs    -- ^ frequency within groups
  , mplayers :: !Players  -- ^ players taking part in the game
  , mcaves   :: !Caves    -- ^ arena of the game
  }
  deriving Show

-- | Requested cave groups for particular levels. The default is
-- the "dng" group, which means a random choice from all caves
-- that can randomly appear. The second component of the pair
-- is the @Escape@ feature on the level. @True@ means it's represented
-- by @<@, @False@, by @>@.
type Caves = EM.EnumMap Int (Text, Maybe Bool)

-- | The specification of players for the game mode.
data Players = Players
  { playersList  :: ![Player]        -- ^ players, both human and computer
  , playersEnemy :: ![(Text, Text)]  -- ^ the initial enmity matrix
  , playersAlly  :: ![(Text, Text)]  -- ^ the initial aliance matrix
  }
  deriving (Show, Eq)

-- | Properties of a particular player.
data Player = Player
  { playerName    :: !Text     -- ^ name of the player
  , playerFaction :: !Text     -- ^ name of faction(s) the player can control
  , playerIsSpawn :: !Bool     -- ^ whether the player is a spawn (score, AI)
  , playerIsHero  :: !Bool     -- ^ whether the player is a hero (score, AI, UI)
  , playerEntry   :: !Int      -- ^ level where the initial members start
  , playerInitial :: !Int      -- ^ number of initial members
  , playerLeader  :: !Bool     -- ^ leaderless factions can't be controlled
                               --   by a human or a user-supplied AI client
  , playerAI      :: !Bool     -- ^ is the faction under AI control?
  , playerUI      :: !Bool     -- ^ does the faction have a UI client
                               --   (for control or passive observation)
  }
  deriving (Show, Eq)

-- TODO: assert every Player's playerName's first word's length <= 15
-- TODO: assert if no UI, both Ai are on and there are some non-spawners;
-- assert that playersEnemy and playersAlly mention only factions in play.
-- | No specific possible problems for the content of this kind, so far,
-- so the validation function always returns the empty list of offending kinds.
validateModeKind :: [ModeKind] -> [ModeKind]
validateModeKind _ = []

instance Binary Player where
  put Player{..} = do
    put playerName
    put playerFaction
    put playerIsSpawn
    put playerIsHero
    put playerEntry
    put playerInitial
    put playerLeader
    put playerAI
    put playerUI
  get = do
    playerName <- get
    playerFaction <- get
    playerIsSpawn <- get
    playerIsHero <- get
    playerEntry <- get
    playerInitial <- get
    playerLeader <- get
    playerAI <- get
    playerUI <- get
    return $! Player{..}
