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
import Wire.Hoogle.Mangle (mangleLink)
import Wire.Hoogle.Types (Config(..), HoogleEntry(..), HoogleResult(..), HoogleUrl(huName), truncateDocs)

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

serverUrl :: Config -> Server -> Text
serverUrl cfg WireServer = cfgWireUrl cfg
serverUrl cfg GeneralServer = cfgGeneralUrl cfg

buildSearchUrl :: Text -> Text -> Int -> Text
buildSearchUrl base query count =
  base
    <> "?mode=json&format=text&hoogle="
    <> T.decodeUtf8With T.lenientDecode (urlEncode True (T.encodeUtf8 query))
    <> "&count="
    <> T.pack (show count)

runQuery :: Manager -> Config -> Server -> QueryParams -> IO (Either QueryError [HoogleEntry])
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
              Right results -> Right (map (toEntry origin (qpFullDocs qp)) results)
  where
    origin = serverUrl cfg server
    url = buildSearchUrl origin (qpQuery qp) (qpCount qp)

toEntry :: Text -> Bool -> HoogleResult -> HoogleEntry
toEntry origin fullDocs r = HoogleEntry
  { hePackage = huName (hrPackage r)
  , heModule = huName (hrModule r)
  , heItem = hrItem r
  , heDocs = docs
  , heDocsTruncated = truncated
  , heLink = mangleLink origin (hrUrl r)
  }
  where
    (docs, truncated) =
      if fullDocs then (hrDocs r, False) else truncateDocs 500 (hrDocs r)