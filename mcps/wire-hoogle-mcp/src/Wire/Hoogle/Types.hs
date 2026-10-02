{-# LANGUAGE OverloadedStrings #-}

module Wire.Hoogle.Types
  ( Config(..)
  , loadConfig
  , HoogleEntry(..)
  , HoogleResult(..)
  , HoogleUrl(..)
  , truncateDocs
  ) where

import Data.Aeson (FromJSON(..), ToJSON(..), object, withObject, (.:), (.:?), (.!=), (.=))
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import System.Environment (lookupEnv)
import Text.Read (readMaybe)

data Config = Config
  { cfgWireUrl :: Text
  , cfgGeneralUrl :: Text
  , cfgCacheMaxEntries :: Int
  }
  deriving (Eq, Show)

defaultWireUrl :: Text
defaultWireUrl = "https://hoogle.zinfra.io"

defaultGeneralUrl :: Text
defaultGeneralUrl = "https://hoogle.haskell.org"

defaultCacheMaxEntries :: Int
defaultCacheMaxEntries = 5000

loadConfig :: IO Config
loadConfig = do
  wireUrl <- envOr "WIRE_HOOGLE_URL" defaultWireUrl
  generalUrl <- envOr "GENERAL_HOOGLE_URL" defaultGeneralUrl
  cacheMax <- envIntOr "HOOGLE_CACHE_MAX_ENTRIES" defaultCacheMaxEntries
  pure (Config wireUrl generalUrl cacheMax)
  where
    envOr :: String -> Text -> IO Text
    envOr name def = maybe def T.pack <$> lookupEnv name
    envIntOr :: String -> Int -> IO Int
    envIntOr name def = do
      v <- lookupEnv name
      pure (maybe def (fromMaybe def . readMaybe) v)

data HoogleUrl = HoogleUrl { huName :: Maybe Text, huUrl :: Maybe Text }
  deriving (Eq, Show)

instance FromJSON HoogleUrl where
  parseJSON = withObject "HoogleUrl" $ \o ->
    HoogleUrl <$> o .:? "name" <*> o .:? "url"

data HoogleResult = HoogleResult
  { hrItem :: Text
  , hrDocs :: Text
  , hrUrl :: Maybe Text
  , hrPackage :: HoogleUrl
  , hrModule :: HoogleUrl
  }
  deriving (Eq, Show)

instance FromJSON HoogleResult where
  parseJSON = withObject "HoogleResult" $ \o ->
    HoogleResult
      <$> o .: "item"
      <*> o .:? "docs" .!= ""
      <*> o .:? "url"
      <*> o .:? "package" .!= HoogleUrl Nothing Nothing
      <*> o .:? "module" .!= HoogleUrl Nothing Nothing

data HoogleEntry = HoogleEntry
  { hePackage :: Maybe Text
  , heModule :: Maybe Text
  , heItem :: Text
  , heDocs :: Text
  , heDocsTruncated :: Bool
  , heLink :: Maybe Text
  }
  deriving (Eq, Show)

instance ToJSON HoogleEntry where
  toJSON e = object
    [ "package" .= hePackage e
    , "module" .= heModule e
    , "item" .= heItem e
    , "docs" .= heDocs e
    , "docs_truncated" .= heDocsTruncated e
    , "link" .= heLink e
    ]

truncateDocs :: Int -> Text -> (Text, Bool)
truncateDocs limit docs
  | T.length docs <= limit = (docs, False)
  | otherwise = (T.take limit docs, True)