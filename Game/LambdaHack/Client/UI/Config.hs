{-# LANGUAGE DeriveGeneric, FlexibleContexts #-}
-- | Personal game configuration file type definitions.
module Game.LambdaHack.Client.UI.Config
  ( Config(..), mkConfig, applyConfigToDebug
  ) where

import Prelude ()

import Game.LambdaHack.Common.Prelude

import Control.DeepSeq
import Data.Binary
import qualified Data.Ini as Ini
import qualified Data.Ini.Reader as Ini
import qualified Data.Ini.Types as Ini
import qualified Data.Map.Strict as M
import qualified Data.Text as T
import Game.LambdaHack.Common.ClientOptions
import GHC.Generics (Generic)
import System.FilePath
import Text.Read

import Game.LambdaHack.Client.UI.HumanCmd
import qualified Game.LambdaHack.Client.UI.Key as K
import Game.LambdaHack.Common.File
import qualified Game.LambdaHack.Common.Kind as Kind
import Game.LambdaHack.Common.Misc
import Game.LambdaHack.Content.RuleKind

-- | Fully typed contents of the UI config file. This config
-- is a part of a game client.
data Config = Config
  { -- commands
    configCommands      :: ![(K.KM, CmdTriple)]
    -- hero names
  , configHeroNames     :: ![(Int, (Text, Text))]
    -- ui
  , configVi            :: !Bool  -- ^ the option for Vi keys takes precendence
  , configLaptop        :: !Bool  -- ^ because the laptop keys are the default
  , configGtkFontFamily :: !Text
  , configSdlFontFile   :: !Text
  , configSdlTtfSizeAdd :: !Int
  , configSdlFonSizeAdd :: !Int
  , configFontSize      :: !Int
  , configColorIsBold   :: !Bool
  , configHistoryMax    :: !Int
  , configMaxFps        :: !Int
  , configNoAnim        :: !Bool
  , configRunStopMsgs   :: !Bool
  , configCmdline       :: ![String]
  }
  deriving (Show, Generic)

instance NFData Config

instance Binary Config

parseConfig :: Ini.Config -> Config
parseConfig cfg =
  let configCommands =
        let mkCommand (ident, keydef) =
              case stripPrefix "Cmd_" ident of
                Just _ ->
                  let (key, def) = read keydef
                  in (K.mkKM key, def :: CmdTriple)
                Nothing -> assert `failure` "wrong macro id" `twith` ident
            section = Ini.allItems "extra_commands" cfg
        in map mkCommand section
      configHeroNames =
        let toNumber (ident, nameAndPronoun) =
              case stripPrefix "HeroName_" ident of
                Just n -> (read n, read nameAndPronoun)
                Nothing -> assert `failure` "wrong hero name id" `twith` ident
            section = Ini.allItems "hero_names" cfg
        in map toNumber section
      getOption :: forall a. Read a => String -> a
      getOption optionName =
        let lookupFail :: forall b. String -> b
            lookupFail err =
              assert `failure` ("config file access failed:" <+> T.pack err)
                     `twith` (optionName, cfg)
            s = fromMaybe (lookupFail "") $ Ini.getOption "ui" optionName cfg
        in either lookupFail id $ readEither s
      configVi = getOption "movementViKeys_hjklyubn"
      -- The option for Vi keys takes precendence,
      -- because the laptop keys are the default.
      configLaptop = not configVi && getOption "movementLaptopKeys_uk8o79jl"
      configGtkFontFamily = getOption "gtkFontFamily"
      configSdlFontFile = getOption "sdlFontFile"
      configSdlTtfSizeAdd = getOption "sdlTtfSizeAdd"
      configSdlFonSizeAdd = getOption "sdlFonSizeAdd"
      configFontSize = getOption "fontSize"
      configColorIsBold = getOption "colorIsBold"
      configHistoryMax = getOption "historyMax"
      configMaxFps = max 1 $ getOption "maxFps"
      configNoAnim = getOption "noAnim"
      configRunStopMsgs = getOption "runStopMsgs"
      configCmdline = words $ getOption "overrideCmdline"
  in Config{..}

-- | Read and parse UI config file.
mkConfig :: Kind.COps -> Bool -> IO Config
mkConfig Kind.COps{corule} benchmark = do
  let stdRuleset = Kind.stdRuleset corule
      cfgUIName = rcfgUIName stdRuleset
      sUIDefault = rcfgUIDefault stdRuleset
      cfgUIDefault = either (assert `failure`) id $ Ini.parse sUIDefault
  dataDir <- appDataDir
  let userPath = dataDir </> cfgUIName
  cfgUser <- if benchmark then return Ini.emptyConfig else do
    cpExists <- doesFileExist userPath
    if not cpExists
      then return Ini.emptyConfig
      else do
        sUser <- readFile userPath
        return $! either (assert `failure`) id $ Ini.parse sUser
  let cfgUI = M.unionWith M.union cfgUser cfgUIDefault  -- user cfg preferred
      conf = parseConfig cfgUI
  -- Catch syntax errors in complex expressions ASAP,
  return $! deepseq conf conf

applyConfigToDebug :: Kind.COps -> Config -> DebugModeCli -> DebugModeCli
applyConfigToDebug Kind.COps{corule} sconfig sdebugCli =
  let stdRuleset = Kind.stdRuleset corule
  in (\dbg -> dbg {sgtkFontFamily =
        sgtkFontFamily dbg `mplus` Just (configGtkFontFamily sconfig)}) .
     (\dbg -> dbg {sdlFontFile =
        sdlFontFile dbg `mplus` Just (configSdlFontFile sconfig)}) .
     (\dbg -> dbg {sdlTtfSizeAdd =
        sdlTtfSizeAdd dbg `mplus` Just (configSdlTtfSizeAdd sconfig)}) .
     (\dbg -> dbg {sdlFonSizeAdd =
        sdlFonSizeAdd dbg `mplus` Just (configSdlFonSizeAdd sconfig)}) .
     (\dbg -> dbg {sfontSize =
        sfontSize dbg `mplus` Just (configFontSize sconfig)}) .
     (\dbg -> dbg {scolorIsBold =
        scolorIsBold dbg `mplus` Just (configColorIsBold sconfig)}) .
     (\dbg -> dbg {smaxFps =
        smaxFps dbg `mplus` Just (configMaxFps sconfig)}) .
     (\dbg -> dbg {snoAnim =
        snoAnim dbg `mplus` Just (configNoAnim sconfig)}) .
     (\dbg -> dbg {stitle =
        stitle dbg `mplus` Just (rtitle stdRuleset)})
     $ sdebugCli
