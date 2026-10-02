module Main (main) where

import Wire.Hoogle.CLI (parseCommand, runCommand)
import Wire.Hoogle.Types (loadConfig)

main :: IO ()
main = do
  command <- parseCommand
  config <- loadConfig
  runCommand command config