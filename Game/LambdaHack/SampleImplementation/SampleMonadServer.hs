{-# LANGUAGE GeneralizedNewtypeDeriving #-}
-- | The main game action monad type implementation. Just as any other
-- component of the library, this implementation can be substituted.
-- This module should not be imported anywhere except in 'Action'
-- to expose the executor to any code using the library.
module Game.LambdaHack.SampleImplementation.SampleMonadServer
  ( executorSer
#ifdef EXPOSE_INTERNAL
    -- * Internal operations
  , SerState(..), SerImplementation(..)
#endif
  ) where

import Prelude ()

import Game.LambdaHack.Common.Prelude

import Control.Concurrent
import qualified Control.Exception as Ex
import qualified Control.Monad.IO.Class as IO
import Control.Monad.Trans.State.Strict hiding (State)
import qualified Data.EnumMap.Strict as EM
import qualified Data.Text.IO as T
import System.FilePath
import System.IO (hFlush, stdout)

import Game.LambdaHack.Atomic
import Game.LambdaHack.Client
import Game.LambdaHack.Client.UI.Config
import Game.LambdaHack.Client.UI.Content.KeyKind
import Game.LambdaHack.Common.ClientOptions
import Game.LambdaHack.Common.File
import qualified Game.LambdaHack.Common.Kind as Kind
import Game.LambdaHack.Common.Misc
import Game.LambdaHack.Common.MonadStateRead
import qualified Game.LambdaHack.Common.Save as Save
import Game.LambdaHack.Common.State
import Game.LambdaHack.Common.Thread
import Game.LambdaHack.SampleImplementation.SampleMonadClient (executorCli)
import Game.LambdaHack.Server
import Game.LambdaHack.Server.BroadcastAtomic
import Game.LambdaHack.Server.HandleAtomicM
import Game.LambdaHack.Server.MonadServer
import Game.LambdaHack.Server.ProtocolM
import Game.LambdaHack.Server.State

data SerState = SerState
  { serState  :: !State           -- ^ current global state
  , serServer :: !StateServer     -- ^ current server state
  , serDict   :: !ConnServerDict  -- ^ client-server connection information
  , serToSave :: !(Save.ChanSave (State, StateServer))
                                  -- ^ connection to the save thread
  }

-- | Server state transformation monad.
newtype SerImplementation a =
    SerImplementation {runSerImplementation :: StateT SerState IO a}
  deriving (Monad, Functor, Applicative)

instance MonadStateRead SerImplementation where
  {-# INLINE getsState #-}
  getsState f = SerImplementation $ gets $ f . serState

instance MonadStateWrite SerImplementation where
  {-# INLINE modifyState #-}
  modifyState f = SerImplementation $ state $ \serS ->
    let !newSerState = f $ serState serS
    in ((), serS {serState = newSerState})

instance MonadServer SerImplementation where
  {-# INLINE getsServer #-}
  getsServer   f = SerImplementation $ gets $ f . serServer
  {-# INLINE modifyServer #-}
  modifyServer f = SerImplementation $ state $ \serS ->
    let !newSerServer = f $ serServer serS
    in ((), serS {serServer = newSerServer})
  saveChanServer = SerImplementation $ gets serToSave
  liftIO         = SerImplementation . IO.liftIO

instance MonadServerReadRequest SerImplementation where
  {-# INLINE getsDict #-}
  getsDict   f = SerImplementation $ gets $ f . serDict
  {-# INLINE modifyDict #-}
  modifyDict f = SerImplementation $ state $ \serS ->
    let !newSerDict = f $ serDict serS
    in ((), serS {serDict = newSerDict})
  liftIO = SerImplementation . IO.liftIO

-- | The game-state semantics of atomic commands
-- as computed on the server.
instance MonadAtomic SerImplementation where
  execUpdAtomic cmd = cmdAtomicSemSer cmd >> handleAndBroadcast (UpdAtomic cmd)
  execSfxAtomic sfx = handleAndBroadcast (SfxAtomic sfx)
  execSendPer = sendPer

-- Don't inline this, to keep GHC hard work inside the library
-- for easy access of code analysis tools.
-- | Run an action in the @IO@ monad, with undefined state.
executorSer :: Kind.COps -> KeyKind -> DebugModeSer -> IO ()
executorSer cops copsClient sdebugNxtCmdline = do
  -- Parse UI client configuration file.
  -- It is reparsed at each start of the game executable.
  sconfig <- mkConfig cops (sbenchmark $ sdebugCli sdebugNxtCmdline)
  sdebugNxt <- case configCmdline sconfig of
    [] -> return sdebugNxtCmdline
    args -> return $! debugArgs args
  -- Options for the clients modified with the configuration file.
  -- The client debug inside server debug only holds the client commandline
  -- options and is never updated with config options, etc.
  let sdebugMode = applyConfigToDebug cops sconfig $ sdebugCli sdebugNxt
      -- Partially applied main loop of the clients.
      executorClient = executorCli (loopCli copsClient sconfig sdebugMode)
  -- Wire together game content, the main loop of game clients
  -- and the game server loop.
  let m = loopSer sdebugNxt sconfig executorClient
      stateToFileName (_, ser) =
        ssavePrefixSer (sdebugSer ser) <.> Save.saveNameSer
      totalState serToSave = SerState
        { serState = emptyState cops
        , serServer = emptyStateServer
        , serDict = EM.empty
        , serToSave
        }
      exe = evalStateT (runSerImplementation m) . totalState
      exeWithSaves = Save.wrapInSaves cops stateToFileName exe
      defPrefix = ssavePrefixSer defDebugModeSer
      bkpOneSave name = do
        dataDir <- appDataDir
        let path bkp = dataDir </> "saves" </> bkp <> name
        b <- doesFileExist (path "")
        when b $ renameFile (path "") (path "bkp.")
      bkpAllSaves = do
        T.hPutStrLn stdout "The game crashed, so savefiles are moved aside."
        bkpOneSave $ defPrefix <.> Save.saveNameSer
        forM_ [-99..99] $ \n ->
          bkpOneSave $ defPrefix <.> Save.saveNameCli (toEnum n)
  -- Wait for clients to exit even in case of server crash
  -- (or server and client crash), which gives them time to save
  -- and report their own inconsistencies, if any.
  Ex.handle (\(ex :: Ex.SomeException) -> do
               Ex.uninterruptibleMask_ $ threadDelay 1000000
                 -- let clients report their errors and save
               when (ssavePrefixSer sdebugNxt == defPrefix) bkpAllSaves
               hFlush stdout
               Ex.throw ex)  -- crash eventually, which kills clients
            exeWithSaves
--  T.hPutStrLn stdout "Server exiting, waiting for clients."
--  hFlush stdout
  waitForChildren childrenServer  -- no crash, wait for clients indefinitely
--  T.hPutStrLn stdout "Server exiting now."
--  hFlush stdout
