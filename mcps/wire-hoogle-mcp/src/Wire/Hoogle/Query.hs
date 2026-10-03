{-# LANGUAGE OverloadedStrings #-}

module Wire.Hoogle.Query
  ( Server(..)
  , QueryParams(..)
  , QueryError(..)
  , serverUrl
  , buildSearchUrl
  , runQuery
  , toEntry
  ) where

import Control.Exception (try)
import Data.Aeson (eitherDecode)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import qualified Data.Text.Encoding.Error as T
import Network.HTTP.Client (HttpException, Manager, httpLbs, parseRequest, responseBody, responseStatus)
import Network.HTTP.Types (statusCode)
import Network.HTTP.Types.URI (urlEncode)
import Network.URI (URI, uriToString)
import Wire.Hoogle.Mangle (mangleLink)
import Wire.Hoogle.Types (CachedEntry(..), Config(..), HoogleResult(..), HoogleUrl(huName))

data Server = WireServer | GeneralServer
  deriving (Eq, Show)

data QueryParams = QueryParams
  { qpQuery :: Text
  , qpCount :: Int
  , qpFullDocs :: Bool
  }
  deriving (Eq, Show)

data QueryError
  = QueryHttp HttpException
  | QueryBadStatus Int
  | QueryParse String
  | QueryBadUrl String
  deriving (Show)

serverUrl :: Config -> Server -> URI
serverUrl cfg WireServer = cfgWireUrl cfg
serverUrl cfg GeneralServer = cfgGeneralUrl cfg

buildSearchUrl :: URI -> Text -> Int -> Text
buildSearchUrl base query count =
  baseString
    <> "?mode=json&format=text&hoogle="
    <> T.decodeUtf8With T.lenientDecode (urlEncode True (T.encodeUtf8 query))
    <> "&count="
    <> T.pack (show count)
  where
    baseString = T.pack (uriToString id base "")

runQuery :: Manager -> Config -> Server -> QueryParams -> IO (Either QueryError [CachedEntry])
runQuery mgr cfg server qp =
  case parseRequest (T.unpack url) of
    Left e -> pure (Left (QueryBadUrl (show e)))
    Right req -> do
      response <- try (httpLbs req mgr)
      pure $ case response of
        Left e -> Left (QueryHttp e)
        Right resp
          | statusCode (responseStatus resp) /= 200 ->
              Left (QueryBadStatus (statusCode (responseStatus resp)))
          | otherwise -> case eitherDecode (responseBody resp) of
              Left e -> Left (QueryParse e)
              Right results -> Right (map (toEntry origin) results)
  where
    origin = serverUrl cfg server
    url = buildSearchUrl origin (qpQuery qp) (qpCount qp)

toEntry :: URI -> HoogleResult -> CachedEntry
toEntry origin r = CachedEntry
  { cePackage = huName (hrPackage r)
  , ceModule = huName (hrModule r)
  , ceItem = hrItem r
  , ceDocs = hrDocs r
  , ceLink = mangleLink origin (hrUrl r)
  , ceSourceLink = Nothing
  , ceType = hrType r
  }