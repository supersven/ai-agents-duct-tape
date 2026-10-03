{-# LANGUAGE OverloadedStrings #-}

module Wire.Hoogle.Mangle (mangleLink) where

import Network.URI (URIAuth(..), URI(..))

-- | Rewrite a docs URL for the instance actually queried: nix-store file:///
-- URLs (an authority-less scheme, i.e. the empty @file:\/\/\/@ form Wire emits)
-- are served by the instance under <origin>/file/...; other URLs pass through
-- unchanged.
mangleLink :: URI -> Maybe URI -> Maybe URI
mangleLink origin (Just url)
  | uriScheme url == "file:" && isEmptyAuthority (uriAuthority url) =
      Just origin
        { uriPath = "/file" <> uriPath url
        , uriQuery = uriQuery url
        , uriFragment = uriFragment url
        }
  | otherwise = Just url
mangleLink _ Nothing = Nothing

-- | network-uri renders an authority-less @file:\/\/\/@ URL as
-- @Just (URIAuth "" "" "")@ (distinct from @file:\/\/host@, which has a
-- non-empty host).
isEmptyAuthority :: Maybe URIAuth -> Bool
isEmptyAuthority (Just auth) =
  null (uriUserInfo auth) && null (uriRegName auth) && null (uriPort auth)
isEmptyAuthority Nothing = False