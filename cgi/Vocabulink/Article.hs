-- Copyright 2008, 2009, 2010, 2011 Chris Forno

-- This file is part of Vocabulink.

-- Vocabulink is free software: you can redistribute it and/or modify it under
-- the terms of the GNU Affero General Public License as published by the Free
-- Software Foundation, either version 3 of the License, or (at your option)
-- any later version.

-- Vocabulink is distributed in the hope that it will be useful, but WITHOUT
-- ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
-- FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License
-- for more details.

-- You should have received a copy of the GNU Affero General Public License
-- along with Vocabulink. If not, see <http://www.gnu.org/licenses/>.

-- All of Vocabulink's @www@ subdomain is served by this program. As such, if
-- we want to publish static data there, we need some outlet for it. The only
-- form of static page we currently display is an article.

module Vocabulink.Article (Article(..), refreshArticles, getArticle, getArticles) where

import Vocabulink.App
import Vocabulink.CGI
import Vocabulink.Utils hiding ((<$$>))

import Control.Monad (filterM)
import System.Directory (getDirectoryContents, getPermissions, doesFileExist, readable)
import qualified System.IO.UTF8 as IO.UTF8
import qualified Text.ParserCombinators.Parsec as P
import Text.ParserCombinators.Parsec.Perm ((<$$>), (<|?>), permute)

-- All articles have some common metadata.

-- The article file path is not strictly necessary to store, but it does allow
-- an article to have a different representation on the filesystem than some
-- translation of its title. This avoids potential problems with automatic
-- title-to-path translation, such as characters that the filesystem doesn't
-- like or articles with very long titles. The filepath however is just the
-- relative filename in the articles directory, not an absolute path.

data Article = Article { articleFilename    :: FilePath
                       , articleAuthor      :: Integer
                       , articlePublishTime :: UTCTime
                       , articleUpdateTime  :: UTCTime
                       , articleSection     :: Maybe String
                       , articleTitle       :: String
                       }

-- For now, article storage is very simple. That may need to change in the
-- future for efficiency and to allow people without access to the article
-- repository to contribute.

-- Retrieving Articles

-- Creating articles is done outside of this program. They are currently
-- generated from Muse-mode files (http://mwolson.org/projects/EmacsMuse.html)
-- using Emacs. However, we can reconstruct the metadata for an article by
-- parsing the file ourselves.

-- Keeping the body of the article outside of the database gives us some of the
-- advantages of the filesystem such as revision control.

-- We need a way of keeping the database consistent with the filesystem. This
-- is it. For a logged in administrator, the articles page displays a ``Refresh
-- from Filesystem'' button that POSTs here.

refreshArticles :: App CGIResult
refreshArticles = do
  h <- asks appDB
  as <- publishedArticles
  liftIO $ withTransaction h $ mapM_ (insertArticle h) as
  redirect =<< referrerOrVocabulink
 where insertArticle h a =
         case articleSection a of
           Nothing -> $(execute
                        "INSERT INTO article (author, \
                                             \title, filename) \
                                     \VALUES ({articleAuthor a}, \
                                             \{articleTitle a}, {articleFilename a})") h
           Just s  -> $(execute
                        "INSERT INTO article (author, \
                                             \section, title, filename) \
                                     \VALUES ({articleAuthor a}, \
                                             \{s}, {articleTitle a}, {articleFilename a})") h

-- Articles are created and updated via the filesystem, but we need to have the
-- metadata on articles available in the database before we can display them
-- via the web. One option is to actually submit articles through the web. But
-- I consider that to be needlessly complex for now. Instead, we can just look
-- over a directory of articles, parse the header of each for metadata, and
-- then update the database.

-- We list the contents of the given directory (non-recursively) and figure out
-- which files are published articles. Finally, we call |getArticle| for each
-- of them. Then we return a list of Articles with undefined numbers and
-- bodies.

publishedArticles :: App [Article]
publishedArticles = do
  dir <- (</> "articles") <$> asks appDir
  ls <- liftIO $ getDirectoryContents dir
  let fullPaths = map (dir </>) ls
  paths <- liftIO $ map takeBaseName <$> filterM isPublished fullPaths
  catMaybes <$> mapM articleFromFile paths

-- We consider an article (file) published if it:

-- * ends with @.muse@
-- * is readable
-- * has a corresponding readable @.html@ file

isPublished :: FilePath -> IO Bool
isPublished f =
  if takeExtension f == ".muse"
    then do
      r1 <- isReadable f
      r2 <- isReadable $ replaceExtension f ".html"
      return $ r1 && r2
    else return False

isReadable :: FilePath -> IO Bool
isReadable f = do
  exists' <- doesFileExist f
  if exists'
    then readable <$> getPermissions f
    else return False

-- To retrieve an article from the filesystem we just need the path to the
-- .muse file. We don't generate the article HTML (that's done by Emacs), so we
-- read that separately from a corresponding .html file. Both files must exist
-- for this to succeed.

articleFromFile :: String -> App (Maybe Article)
articleFromFile path = do
  dir  <- (</> "articles") <$> asks appDir
  muse <- liftIO $ IO.UTF8.readFile $ dir </> path <.> "muse"
  case P.parse articleHeader "" muse of
    Left e    -> liftIO $ logError "parse" (show e) >> return Nothing
    Right hdr -> return $ Just $ hdr {  articleFilename  = path }

-- Each article is expected to have a particular structure. The structure is
-- based off of a required subset of the Muse-mode directives.

-- An accepted article's first lines will consist of something like:

-- #title Why Learn with Vocabulink?
-- #author jekor
-- #date 2009-01-11 16:04 -0800
-- #update 2009-02-28 14:55 -0800
-- #section main

-- #title:   is a freeform title.
-- #author:  must be a username from the members table.
-- #date:    is the date in ISO-8601 format (with spaces between the date,
--           time, and timezone).
-- #update:  is an optional update time (in the same format as @#date@).
-- #section: is the section of the site in to publish the article. For
--           static content ``articles'' such as the privacy policy, don't
--           include a section. For now, only ``main'' is supported with
--           our simple publishing system.

-- Parsing an article's metadata is pretty simple with Parsec's permutation
-- combinators.

-- We're going to go ahead and use fromJust here because we don't care about
-- how we're notified of errors (publishing articles is not (yet)
-- member-facing).

articleHeader :: P.Parser Article
articleHeader = permute
  (mkArticle <$$> museDirective "title"
             <|?> (Nothing, Just <$> museDirective "section"))
    where mkArticle title section =
            Article { articleFilename    = undefined
                    , articleAuthor      = 1 -- currently only jekor can publish articles
                    , articlePublishTime = undefined
                    , articleUpdateTime  = undefined
                    , articleSection     = section
                    , articleTitle       = title
                    }

-- A muse directive looks sort of like a C preprocessor directive.

museDirective :: String -> P.Parser String
museDirective dir = museDir dir >> P.manyTill P.anyChar P.newline

museDir :: String -> P.Parser ()
museDir dir = P.try (P.string ('#' : dir)) >> P.spaces

-- Retrieving Articles

-- To retrieve an article with need its (relative) filename (or path, or
-- whatever you want to call it).

getArticle :: String -> App (Maybe Article)
getArticle filename = liftM articleFromTuple <$> $(queryTuple'
  "SELECT filename, author, publish_time, \
         \update_time, section, title \
  \FROM article WHERE filename = {filename}")

-- As with links, we use a helper function to convert a raw SQL tuple.

articleFromTuple :: (FilePath, Integer, UTCTime, UTCTime, Maybe String, String) -> Article
articleFromTuple (f, a, p, u, s, t) =
  Article { articleFilename     = f
          , articleAuthor       = a
          , articlePublishTime  = p
          , articleUpdateTime   = u
          , articleSection      = s
          , articleTitle        = t
          }

-- To get a list of articles for display on the main articles page, we look for
-- published articles in the database that are in the ``main'' section.

getArticles :: App [Article]
getArticles = map articleFromTuple <$> $(queryTuples'
  "SELECT filename, author, publish_time, \
         \update_time, section, title \
  \FROM article \
  \WHERE publish_time < CURRENT_TIMESTAMP \
    \AND section = 'main' \
  \ORDER BY publish_time DESC")