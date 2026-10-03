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
  , uriToText
  ) where

import Data.Aeson (FromJSON(..), ToJSON(..), object, withObject, (.:), (.:?), (.!=), (.=))
import Data.Aeson.Types (Parser)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Network.URI (URI, parseURI, uriToString)
import System.Environment (lookupEnv)
import Text.Read (readMaybe)

data Config = Config
  { cfgWireUrl :: URI
  , cfgGeneralUrl :: URI
  , cfgCacheMaxEntries :: Int
  }
  deriving (Eq, Show)

defaultWireUrl :: URI
defaultWireUrl = parseURIorDie "https://hoogle.zinfra.io"

defaultGeneralUrl :: URI
defaultGeneralUrl = parseURIorDie "https://hoogle.haskell.org"

defaultCacheMaxEntries :: Int
defaultCacheMaxEntries = 5000

parseURIorDie :: String -> URI
parseURIorDie s = fromMaybe (error ("invalid default hoogle URL: " ++ s)) (parseURI s)

loadConfig :: IO Config
loadConfig = do
  wireUrl <- envOr "WIRE_HOOGLE_URL" defaultWireUrl
  generalUrl <- envOr "GENERAL_HOOGLE_URL" defaultGeneralUrl
  cacheMax <- max 1 <$> envIntOr "HOOGLE_CACHE_MAX_ENTRIES" defaultCacheMaxEntries
  pure (Config wireUrl generalUrl cacheMax)
  where
    envOr :: String -> URI -> IO URI
    envOr name def = do
      v <- lookupEnv name
      pure (maybe def (fromMaybe def . parseURI) v)
    envIntOr :: String -> Int -> IO Int
    envIntOr name def = do
      v <- lookupEnv name
      pure (maybe def (fromMaybe def . readMaybe) v)

data HoogleUrl = HoogleUrl { huName :: Maybe Text, huUrl :: Maybe URI }
  deriving (Eq, Show)

instance FromJSON HoogleUrl where
  parseJSON = withObject "HoogleUrl" $ \o -> do
    name <- o .:? "name"
    url <- o .:? "url" :: Parser (Maybe Text)
    pure (HoogleUrl name (url >>= parseURI . T.unpack))

data HoogleResult = HoogleResult
  { hrItem :: Text
  , hrDocs :: Text
  , hrUrl :: Maybe URI
  , hrPackage :: HoogleUrl
  , hrModule :: HoogleUrl
  , hrType :: Text
  }
  deriving (Eq, Show)

instance FromJSON HoogleResult where
  parseJSON = withObject "HoogleResult" $ \o -> do
    item <- o .: "item"
    docs <- o .:? "docs" .!= ""
    url <- o .:? "url" :: Parser (Maybe Text)
    package <- o .:? "package" .!= HoogleUrl Nothing Nothing
    module' <- o .:? "module" .!= HoogleUrl Nothing Nothing
    type' <- o .:? "type" .!= ""
    pure (HoogleResult item docs (url >>= parseURI . T.unpack) package module' type')

-- | What the cache stores: full, untruncated docs, mangled link, and the
-- resolved haddock "Source" link. Nothing derived per request (no truncation
-- flag); the source link needs a docs-page fetch, so it is resolved at query
-- time and cached.
data CachedEntry = CachedEntry
  { cePackage :: Maybe Text
  , ceModule :: Maybe Text
  , ceItem :: Text
  , ceDocs :: Text
  , ceLink :: Maybe URI
  , ceSourceLink :: Maybe URI
  , ceType :: Text
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
  , oeType :: Maybe Text
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
    , "type" .= oeType e
    ]

-- | Render a 'URI' to its canonical string form.
uriToText :: URI -> Text
uriToText u = T.pack (uriToString id u "")

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
  , oeLink = uriToText <$> ceLink entry
  , oeSourceLink = uriToText <$> ceSourceLink entry
  , oeType = type'
  }
  where
    (docs, truncated) =
      if fullDocs then (ceDocs entry, False) else truncateDocs 500 (ceDocs entry)
    type' = if T.null (ceType entry) then Nothing else Just (ceType entry)