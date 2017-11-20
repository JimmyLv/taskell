module UI.List where

import Data.Sequence (mapWithIndex) 
import Data.Foldable (toList)
import Data.Sequence (Seq)
import Graphics.Vty

import UI.Task (present)
import Data.Taskell.Task (Tasks)

attrTitle :: Attr
attrTitle = defAttr `withForeColor` green

attrCurrent :: Attr
attrCurrent = defAttr `withForeColor` blue

attrNoItems :: Attr
attrNoItems = defAttr `withStyle` dim 

title :: Bool -> String -> Image
title current t = string style t 
    where style = if current then attrCurrent else attrTitle

noItems :: Image
noItems = string attrNoItems "No items"

tasksToImage :: Seq Image -> Image
tasksToImage = vertCat . toList 

-- passing current and index feels inelegant...
mapTasks :: Bool -> Int -> Tasks -> Image
mapTasks current index = tasksToImage . mapWithIndex (present current index)

list :: String -> Bool -> Int -> Tasks -> Image
list name current index tasks = (title current name) <-> items
    where items = if length tasks /= 0 then (mapTasks current index tasks) else noItems 