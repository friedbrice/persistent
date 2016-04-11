{-# LANGUAGE CPP #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
module Database.Persist.Class.PersistQuery
    ( PersistQueryRead (..)
    , PersistQueryWrite (..)
    , selectSource
    , selectKeys
    , selectList
    , selectKeysList
    ) where

import Database.Persist.Types
import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Reader   (ReaderT, MonadReader)

import qualified Data.Conduit as C
import qualified Data.Conduit.List as CL
import Database.Persist.Class.PersistStore
import Database.Persist.Class.PersistEntity
import Control.Monad.Trans.Resource (MonadResource, release)
import Data.Acquire (Acquire, allocateAcquire, with)

-- | Backends supporting conditional read operations.
class (PersistCore backend, PersistStoreRead backend) => PersistQueryRead backend where
    -- | Get all records matching the given criterion in the specified order.
    -- Returns also the identifiers.
    selectSourceRes
           :: (PersistEntity val, PersistEntityBackend val ~ BaseBackend backend, MonadIO m1, MonadIO m2)
           => [Filter val]
           -> [SelectOpt val]
           -> ReaderT backend m1 (Acquire (C.Source m2 (Entity val)))

    -- | Get just the first record for the criterion.
    selectFirst :: (MonadIO m, PersistEntity val, BaseBackend backend ~ PersistEntityBackend val)
                => [Filter val]
                -> [SelectOpt val]
                -> ReaderT backend m (Maybe (Entity val))
    selectFirst filts opts = do
        srcRes <- selectSourceRes filts (LimitTo 1 : opts)
        liftIO $ with srcRes (C.$$ CL.head)

    -- | Get the 'Key's of all records matching the given criterion.
    selectKeysRes
        :: (MonadIO m1, MonadIO m2, PersistEntity val, BaseBackend backend ~ PersistEntityBackend val)
        => [Filter val]
        -> [SelectOpt val]
        -> ReaderT backend m1 (Acquire (C.Source m2 (Key val)))

    -- | The total number of records fulfilling the given criterion.
    count :: (MonadIO m, PersistEntity val, BaseBackend backend ~ PersistEntityBackend val)
          => [Filter val] -> ReaderT backend m Int

-- | Backends supporting conditional write operations
class (PersistQueryRead backend, PersistStoreWrite backend) => PersistQueryWrite backend where
    -- | Update individual fields on any record matching the given criterion.
    updateWhere :: (MonadIO m, PersistEntity val, BaseBackend backend ~ PersistEntityBackend val)
                => [Filter val] -> [Update val] -> ReaderT backend m ()

    -- | Delete all records matching the given criterion.
    deleteWhere :: (MonadIO m, PersistEntity val, BaseBackend backend ~ PersistEntityBackend val)
                => [Filter val] -> ReaderT backend m ()

-- | Get all records matching the given criterion in the specified order.
-- Returns also the identifiers.
selectSource
       :: (PersistQueryRead (BaseBackend backend), MonadResource m, PersistEntity val, PersistEntityBackend val ~ BaseBackend (BaseBackend backend), MonadReader backend m, HasPersistBackend backend)
       => [Filter val]
       -> [SelectOpt val]
       -> C.Source m (Entity val)
selectSource filts opts = do
    srcRes <- liftPersist $ selectSourceRes filts opts
    (releaseKey, src) <- allocateAcquire srcRes
    src
    release releaseKey

-- | Get the 'Key's of all records matching the given criterion.
selectKeys :: (PersistQueryRead (BaseBackend backend), MonadResource m, PersistEntity val, BaseBackend (BaseBackend backend) ~ PersistEntityBackend val, MonadReader backend m, HasPersistBackend backend)
           => [Filter val]
           -> [SelectOpt val]
           -> C.Source m (Key val)
selectKeys filts opts = do
    srcRes <- liftPersist $ selectKeysRes filts opts
    (releaseKey, src) <- allocateAcquire srcRes
    src
    release releaseKey

-- | Call 'selectSource' but return the result as a list.
selectList :: (MonadIO m, PersistEntity val, PersistQueryRead backend, PersistEntityBackend val ~ BaseBackend backend)
           => [Filter val]
           -> [SelectOpt val]
           -> ReaderT backend m [Entity val]
selectList filts opts = do
    srcRes <- selectSourceRes filts opts
    liftIO $ with srcRes (C.$$ CL.consume)

-- | Call 'selectKeys' but return the result as a list.
selectKeysList :: (MonadIO m, PersistEntity val, PersistQueryRead backend, PersistEntityBackend val ~ BaseBackend backend)
               => [Filter val]
               -> [SelectOpt val]
               -> ReaderT backend m [Key val]
selectKeysList filts opts = do
    srcRes <- selectKeysRes filts opts
    liftIO $ with srcRes (C.$$ CL.consume)
