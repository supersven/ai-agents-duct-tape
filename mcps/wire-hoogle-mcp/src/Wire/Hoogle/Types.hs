{-# LANGUAGE OverloadedStrings #-}

module Wire.Hoogle.Types
  ( Config(..)
  , loadConfig
  , CachedEntry(..)
  , OutputEntry(..)
  , HoogleResult(..)
  , HoogleUrl(..)
  , truncateDocs
  , toOutputEntry
  ) where

import Data.Aeson (FromJSON(..), ToJSON(..), object, withObject, (.:), (.:?), (.!=), (.=))
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import System.Environment (lookupEnv)
import Text.Read (readMaybe)
import Wire.Hoogle.Mangle (deriveSourceLink)

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
  cacheMax <- max 1 <$> envIntOr "HOOGLE_CACHE_MAX_ENTRIES" defaultCacheMaxEntries
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

-- | What the cache stores: full, untruncated docs, mangled link, and nothing
-- derived per request (no truncation flag, no source link).
data CachedEntry = CachedEntry
  { cePackage :: Maybe Text
  , ceModule :: Maybe Text
  , ceItem :: Text
  , ceDocs :: Text
  , ceLink :: Maybe Text
  }
  deriving (Eq, Show)

-- | What is served to the agent: docs truncated to ~500 chars unless full docs
-- were requested, plus the derived source link.
data OutputEntry = OutputEntry
  { oePackage :: Maybe Text
  , oeModule :: Maybe Text
  , oeItem :: Text
  , oeDocs :: Text
  , oeDocsTruncated :: Bool
  , oeLink :: Maybe Text
  , oeSourceLink :: Maybe Text
  }
  deriving (Eq, Show)

instance ToJSON OutputEntry where
  toJSON e = object
    [ "package" .= oePackage e
    , "module" .= oeModule e
    , "item" .= oeItem e
    , "docs" .= oeDocs e
    , "docs_truncated" .= oeDocsTruncated e
    , "link" .= oeLink e
    , "source_link" .= oeSourceLink e
    ]

truncateDocs :: Int -> Text -> (Text, Bool)
truncateDocs limit docs
  | T.length docs <= limit = (docs, False)
  | otherwise = (T.take limit docs, True)

toOutputEntry :: Bool -> CachedEntry -> OutputEntry
toOutputEntry fullDocs entry = OutputEntry
  { oePackage = cePackage entry
  , oeModule = ceModule entry
  , oeItem = ceItem entry
  , oeDocs = docs
  , oeDocsTruncated = truncated
  , oeLink = ceLink entry
  , oeSourceLink = deriveSourceLink =<< ceLink entry
  }
  where
    (docs, truncated) =
      if fullDocs then (ceDocs entry, False) else truncateDocs 500 (ceDocs entry)