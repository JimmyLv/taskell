module Flow.State where

import Data.Taskell.Task (Tasks, Task, extract, split, empty, swap, update, append, backspace, blank)
import Data.Maybe (fromMaybe)
import Data.Sequence ((><), (|>)) 

data CurrentList = ToDo | Done deriving (Show, Eq)

data State = State {
    running :: Bool, -- whether the app is running
    insert :: Bool,
    tasks :: (Tasks, Tasks), -- the todo and done tasks 
    current :: (CurrentList, Int) -- the list and index
} deriving (Show)

initial :: State
initial = State {
        running = True,
        insert = False,
        tasks = (empty, empty),
        current = (ToDo, 0)
    } 

-- app state
quit :: State -> State
quit s = s { running = False }

-- insert
startInsert :: State -> State
startInsert s = s { insert = True }

finishInsert :: State -> State
finishInsert s = s { insert = False }

newItem :: State -> State
newItem s = setToDo indexed (getToDo indexed |> blank)
    where listed = setList s ToDo 
          indexed = setIndex listed (count ToDo listed)

change :: (Task -> Task) -> State -> State
change fn s = case getList s of
    ToDo -> setToDo s $ update' $ getToDo s
    Done -> setDone s $ update' $ getDone s
    where update' = update (getIndex s) fn

insertBS :: State -> State
insertBS = change backspace

insertCurrent :: Char -> State -> State
insertCurrent = change . append

-- list and index
count :: CurrentList -> State -> Int
count ToDo = length . getToDo
count Done = length . getDone

countCurrent :: State -> Int
countCurrent s = count (getList s) s

setIndex :: State -> Int -> State
setIndex s i = s { current = (getList s, i) }

setList :: State -> CurrentList -> State
setList s l = s { current = (l, getIndex s) }

getIndex :: State -> Int
getIndex = snd . current

getList :: State -> CurrentList
getList = fst . current

shiftIndex :: (Int -> Int) -> State -> State
shiftIndex fn s = setIndex s x 
    where
        list = getList s
        inc = fn $ getIndex s
        c = count list s
        x = if c /= 0 then inc `mod` c else 0 

next :: State -> State
next = shiftIndex succ

previous :: State -> State
previous = shiftIndex pred

switch :: State -> State
switch s = fixIndex $ case getList s of
    ToDo -> setList s Done
    Done -> setList s ToDo

fixIndex :: State -> State
fixIndex s = if getIndex s > c then setIndex s c' else s
    where c = countCurrent s - 1
          c' = if c < 0 then 0 else c

-- tasks
getDone :: State -> Tasks
getDone = snd . tasks

getToDo :: State -> Tasks
getToDo = fst . tasks

setDone :: State -> Tasks -> State
setDone s ts = s { tasks = (getToDo s, ts) }

setToDo :: State -> Tasks -> State
setToDo s ts = s { tasks = (ts, getDone s) }

setTasks :: State -> Tasks -> State
setTasks s ts = s { tasks = split ts }

getTasks :: State -> Tasks
getTasks s = uncurry (><) (tasks s)

-- completed
toggle :: (State -> Tasks, State -> Tasks) -> (State -> Tasks -> State, State -> Tasks -> State) -> State -> Maybe State
toggle (fromGet, toGet) (fromSet, toSet) s = do
    (removed, current) <- extract (getIndex s) (fromGet s)
    let updated = toSet s (toGet s |> swap current)
    let final = fromSet updated removed
    return $ fixIndex final

toggleCompleted' :: State -> Maybe State
toggleCompleted' s = case getList s of
    ToDo -> toggle (getToDo, getDone) (setToDo, setDone) s
    Done -> toggle (getDone, getToDo) (setDone, setToDo) s

toggleCompleted :: State -> State
toggleCompleted s = fromMaybe s (toggleCompleted' s)
