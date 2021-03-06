module System

import public Data.So
import Data.List
import Data.Strings

support : String -> String
support fn = "C:" ++ fn ++ ", libidris2_support"

libc : String -> String
libc fn = "C:" ++ fn ++ ", libc 6"

%foreign support "idris2_sleep"
prim_sleep : Int -> PrimIO ()
%foreign support "idris2_usleep"
prim_usleep : Int -> PrimIO ()

export
sleep : HasIO io => Int -> io ()
sleep sec = primIO (prim_sleep sec)

export
usleep : HasIO io => (x : Int) -> So (x >= 0) => io ()
usleep sec = primIO (prim_usleep sec)

-- This one is going to vary for different back ends. Probably needs a
-- better convention. Will revisit...
%foreign "scheme:blodwen-args"
         "node:lambda:() => __prim_js2idris_array(process.argv.slice(1))"
prim__getArgs : PrimIO (List String)

export
getArgs : HasIO io => io (List String)
getArgs = primIO prim__getArgs

%foreign libc "getenv"
         "node:lambda: n => process.env[n]"
prim_getEnv : String -> PrimIO (Ptr String)

%foreign support "idris2_getEnvPair"
prim_getEnvPair : Int -> PrimIO (Ptr String)
%foreign support "idris2_setenv"
prim_setEnv : String -> String -> Int -> PrimIO Int
%foreign support "idris2_unsetenv"
prim_unsetEnv : String -> PrimIO Int

export
getEnv : HasIO io => String -> io (Maybe String)
getEnv var
   = do env <- primIO $ prim_getEnv var
        if prim__nullPtr env /= 0
           then pure Nothing
           else pure (Just (prim__getString env))

export
getEnvironment : HasIO io => io (List (String, String))
getEnvironment = getAllPairs 0 []
  where
    splitEq : String -> (String, String)
    splitEq str
        = let (k, v)  = break (== '=') str
              (_, v') = break (/= '=') v in
              (k, v')

    getAllPairs : Int -> List String -> io (List (String, String))
    getAllPairs n acc = do
      envPair <- primIO $ prim_getEnvPair n
      if prim__nullPtr envPair /= 0
         then pure $ reverse $ map splitEq acc
         else getAllPairs (n + 1) (prim__getString envPair :: acc)

export
setEnv : HasIO io => String -> String -> Bool -> io Bool
setEnv var val overwrite
   = do ok <- primIO $ prim_setEnv var val (if overwrite then 1 else 0)
        pure $ ok == 0

export
unsetEnv : HasIO io => String -> io Bool
unsetEnv var
   = do ok <- primIO $ prim_unsetEnv var
        pure $ ok == 0

%foreign libc "system"
         "scheme:blodwen-system"
prim_system : String -> PrimIO Int

export
system : HasIO io => String -> io Int
system cmd = primIO (prim_system cmd)

%foreign support "idris2_time"
         "scheme:blodwen-time"
prim_time : PrimIO Int

export
time : HasIO io => io Integer
time = pure $ cast !(primIO prim_time)

%foreign libc "exit"
         "node:lambda:c => process.exit(Number(c))"
prim_exit : Int -> PrimIO ()

||| Programs can either terminate successfully, or end in a caught
||| failure.
public export
data ExitCode : Type where
  ||| Terminate successfully.
  ExitSuccess : ExitCode
  ||| Program terminated for some prescribed reason.
  |||
  ||| @errNo A non-zero numerical value indicating failure.
  ||| @prf   Proof that the int value is non-zero.
  ExitFailure : (errNo    : Int) -> (So (not $ errNo == 0)) => ExitCode

export
exitWith : HasIO io => ExitCode -> io a
exitWith ExitSuccess = primIO $ believe_me $ prim_exit 0
exitWith (ExitFailure code) = primIO $ believe_me $ prim_exit code

||| Exit the program indicating failure.
export
exitFailure : HasIO io => io a
exitFailure = exitWith (ExitFailure 1)

||| Exit the program after a successful run.
export
exitSuccess : HasIO io => io a
exitSuccess = exitWith ExitSuccess
