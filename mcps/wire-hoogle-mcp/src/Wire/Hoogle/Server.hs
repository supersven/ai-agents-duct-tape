{-# LANGUAGE OverloadedStrings #-}

module Wire.Hoogle.Server (runServer, toolList) where

import qualified Data.Aeson as Aeson (encode)
import qualified Data.ByteString.Lazy.Char8 as BL8
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import Data.Text.Read (decimal)
import Data.Version (showVersion)
import MCP.Server
  ( Content(..)
  , Error(..)
  , InputSchemaDefinition(..)
  , InputSchemaDefinitionProperty(..)
  , McpServerHandlers(..)
  , McpServerInfo(..)
  , ToolDefinition(..)
  , runMcpServerStdio
  )
import Network.HTTP.Client (Manager, managerResponseTimeout, newManager, responseTimeoutMicro)
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Paths_wire_hoogle_mcp (version)
import Wire.Hoogle.Cache (Caches, cachedQuery, newCaches)
import Wire.Hoogle.Query (QueryParams(..), Server(..))
import Wire.Hoogle.Types (Config(..))

runServer :: Config -> IO ()
runServer cfg = do
  manager <- newManager tlsManagerSettings { managerResponseTimeout = responseTimeoutMicro 30000000 }
  caches <- newCaches (cfgCacheMaxEntries cfg)
  let serverInfo = McpServerInfo
        { serverName = "wire-hoogle"
        , serverVersion = T.pack (showVersion version)
        , serverInstructions =
            "Provides the 'hoogle' tool for Haskell API lookup. It queries the \
            \Wire Hoogle instance by default and the general instance only when \
            \'general' is set (packages not yet in the project). 'query' is a \
            \Hoogle query, not a plain search: scope results with \
            \+packagename / -packagename / +Module.Name (see the tool \
            \description)."
        }
      handlers = McpServerHandlers
        { prompts = Nothing
        , resources = Nothing
        , tools = Just (toolList, toolCall manager caches cfg)
        }
  runMcpServerStdio serverInfo handlers

toolList :: IO [ToolDefinition]
toolList = pure
  [ ToolDefinition
      { toolDefinitionName = "hoogle"
      , toolDefinitionDescription =
          "Search Haskell API documentation with Hoogle. 'query' is a Hoogle \
          \query, NOT a plain text search. It supports type signatures \
          \('a -> a', 'Text -> IO ()'), names ('map'), combined \
          \'name :: type' ('readFile :: FilePath -> IO String'), and scope \
          \filters: '+packagename' restricts to a package (e.g. 'map +base'), \
          \'-packagename' excludes one (e.g. 'map -ghc-internal'), and \
          \'+Module.Name' restricts to a module (e.g. 'foldl' +Data.List'). \
          \A leading '::' forces a type-only search. The Wire Hoogle instance \
          \(default) indexes the project's packages; set 'general' to true \
          \ONLY for a package not yet in the project (rare). Results are JSON: \
          \package, module, item (signature), docs, docs_truncated, link, \
          \source_link, type, also_in. Results are deduplicated by \
          \source_link: a definition re-exported by several modules appears \
          \once, with the other package/module locations listed in 'also_in'."
      , toolDefinitionInputSchema = InputSchemaDefinitionObject
          { properties =
              [ ("query", InputSchemaDefinitionProperty "string" "Hoogle query, not a plain search (see syntax in the tool description)")
              , ("general", InputSchemaDefinitionProperty "boolean" "Search the general hoogle instance (hoogle.haskell.org) instead of Wire; only for packages not yet in the project")
              , ("count", InputSchemaDefinitionProperty "integer" "Maximum number of results, clamped to 1..50 (default: 10); deduplication by source_link may return fewer")
              , ("full_docs", InputSchemaDefinitionProperty "boolean" "Return full docs instead of truncating to ~500 chars")
              ]
          , required = [ "query" ]
          }
      , toolDefinitionTitle = Nothing
      }
  ]

toolCall :: Manager -> Caches -> Config -> Text -> [(Text, Text)] -> IO (Either Error Content)
toolCall manager caches cfg toolName args
  | toolName /= "hoogle" = pure (Left (UnknownTool toolName))
  | otherwise =
      case lookup "query" args of
        Nothing -> pure (Left (InvalidParams "missing required argument 'query'"))
        Just query ->
          let qp = QueryParams
                { qpQuery = query
                , qpCount = min 50 (max 1 (fromMaybe 10 (readInt =<< lookup "count" args)))
                , qpFullDocs = lookup "full_docs" args == Just "true"
                }
              server = if lookup "general" args == Just "true" then GeneralServer else WireServer
          in do
            result <- cachedQuery manager caches cfg server qp
            pure $ case result of
              Left err -> Left (InternalError (T.pack (show err)))
              Right entries -> Right (ContentText (T.decodeUtf8 (BL8.toStrict (Aeson.encode entries))))
  where
    readInt :: Text -> Maybe Int
    readInt t = case decimal t of
      Right (n, rest) | T.null rest -> Just n
      _ -> Nothing