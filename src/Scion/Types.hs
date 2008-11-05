-- |
-- Module      : Scion.Types
-- Copyright   : (c) Thomas Schilling 2008
-- License     : BSD-style
--
-- Maintainer  : nominolo@gmail.com
-- Stability   : experimental
-- Portability : portable
--
-- Core types used throughout Scion. 
--
module Scion.Types 
  ( module Scion.Types
  , liftIO, MonadIO
  ) where

import GHC
import HscTypes
import MonadUtils ( liftIO, MonadIO )
import Exception
import qualified GHC

import Distribution.Simple.LocalBuildInfo
import Control.Monad ( when )
import Data.IORef

data SessionState 
  = SessionState {
      scionVerbosity :: Verbosity,
      localBuildInfo :: Maybe LocalBuildInfo
    }

mkSessionState :: IO (IORef SessionState)
mkSessionState = newIORef (SessionState normal Nothing)

newtype ScionM a
  = ScionM { unScionM :: IORef SessionState -> Ghc a }

instance Monad ScionM where
  return x = ScionM $ \_ -> return x
  (ScionM ma) >>= fb = 
      ScionM $ \s -> do
        a <- ma s 
        unScionM (fb a) s             

instance Functor ScionM where
  fmap f (ScionM ma) =
      ScionM $ \s -> fmap f (ma s)

liftScionM :: Ghc a -> ScionM a
liftScionM m = ScionM $ \_ -> m

instance MonadIO ScionM where
  liftIO m = liftScionM $ liftIO m

instance ExceptionMonad ScionM where
  gcatch (ScionM act) handler =
      ScionM $ \s -> act s `gcatch` (\e -> unScionM (handler e) s)
  gblock (ScionM act) = ScionM $ \s -> gblock (act s)
  gunblock (ScionM act) = ScionM $ \s -> gunblock (act s)

instance WarnLogMonad ScionM where
  setWarnings = liftScionM . setWarnings
  getWarnings = liftScionM getWarnings

instance GhcMonad ScionM where
  getSession = liftScionM getSession
  setSession = liftScionM . setSession

modifySessionState :: (SessionState -> SessionState) -> ScionM ()
modifySessionState mod = 
    ScionM $ \r -> liftIO $ do s <- readIORef r; writeIORef r $! mod s

getSessionState :: ScionM SessionState
getSessionState = ScionM $ \s -> liftIO $ readIORef s

gets :: (SessionState -> a) -> ScionM a
gets sel = getSessionState >>= return . sel

setSessionState :: SessionState -> ScionM ()
setSessionState s' = ScionM $ \r -> liftIO $ writeIORef r s'

data Verbosity
  = Silent
  | Normal
  | Verbose
  | Deafening
  deriving (Eq, Ord, Show, Enum, Bounded)

silent :: Verbosity
silent = Silent

normal :: Verbosity
normal = Normal

verbose :: Verbosity
verbose = Verbose

deafening :: Verbosity
deafening = Deafening

message :: Verbosity -> String -> ScionM ()
message v s = do
  v0 <- gets scionVerbosity
  when (v0 >= v) $ liftIO $ putStrLn s

-- | Reflect a computation in the 'ScionM' monad into the 'IO' monad.
reflectScionM :: ScionM a -> (IORef SessionState, Session) -> IO a
reflectScionM (ScionM f) = \(st, sess) -> reflectGhc (f st) sess

-- > Dual to 'reflectGhc'.  See its documentation.
reifyScionM :: ((IORef SessionState, Session) -> IO a) -> ScionM a
reifyScionM act = ScionM $ \st -> reifyGhc $ \sess -> act (st, sess)
