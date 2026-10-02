{-# LANGUAGE OverloadedStrings #-}

module Wire.Hoogle.CLI
  ( Command(..)
  , QueryOptions(..)
  , parseCommand
  , runCommand
  ) where

import Data.Aeson (encode)
import qualified Data.ByteString.Lazy as BL
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import qualified Data.Text.IO as TIO
import Network.HTTP.Client (newManager)
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Options.Applicative
  ( Parser
  , auto
  , command
  , execParser
  , flag
  , fullDesc
  , header
  , help
  , helper
  , hsubparser
  , info
  , long
  , metavar
  , option
  , progDesc
  , short
  , strArgument
  , switch
  , value
  , (<|>)
  )
import System.Exit (exitFailure)
import System.IO (stderr)
import Wire.Hoogle.Cache (cachedQuery, newHoogleCache)
import Wire.Hoogle.Query (QueryParams(..), Server(..))
import Wire.Hoogle.Server (runServer)
import Wire.Hoogle.Types (Config(..))

data QueryOptions = QueryOptions
  { qoQuery :: Text
  , qoCount :: Int
  , qoFullDocs :: Bool
  , qoServer :: Maybe Server
  }
  deriving (Eq, Show)

data Command = CommandServe | CommandQuery QueryOptions
  deriving (Eq, Show)

queryParser :: Parser QueryOptions
queryParser = QueryOptions
  <$> (T.pack <$> strArgument (metavar "QUERY" <> help "Hoogle query, not a plain search (see --help)"))
  <*> option auto (long "count" <> short 'n' <> value 10 <> metavar "N" <> help "Maximum number of results (default: 10)")
  <*> switch (long "full-docs" <> help "Return full docs instead of truncating to ~500 chars")
  <*> (flag Nothing (Just GeneralServer) (long "general" <> help "Search the general hoogle instance (hoogle.haskell.org) instead of Wire"))

commandParser :: Parser Command
commandParser =
  (pure CommandServe)
    <|> hsubparser
      ( command "query"
          ( info (CommandQuery <$> queryParser)
              ( progDesc "Query hoogle and print the mangled JSON results to stdout"
              )
          )
      )

parseCommand :: IO Command
parseCommand =
  execParser
    ( info
        (helper <*> commandParser)
        ( fullDesc
            <> progDesc "Hoogle MCP server (default) or hoogle query CLI"
            <> header "wire-hoogle-mcp"
        )
    )

runCommand :: Command -> Config -> IO ()
runCommand CommandServe cfg = runServer cfg
runCommand (CommandQuery qo) cfg = do
  manager <- newManager tlsManagerSettings
  cache <- newHoogleCache (cfgCacheMaxEntries cfg)
  let server = fromMaybe WireServer (qoServer qo)
      qp = QueryParams (qoQuery qo) (qoCount qo) (qoFullDocs qo)
  result <- cachedQuery manager cache cfg server qp
  case result of
    Left err -> TIO.hPutStrLn stderr ("error: " <> T.pack (show err)) >> exitFailure
    Right entries -> TIO.putStrLn (T.decodeUtf8 (toStrict (encode entries)))
  where
    toStrict = BL.toStrict