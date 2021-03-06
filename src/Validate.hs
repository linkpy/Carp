module Validate where

import TypeError
import Obj
import Types
import Util
import Lookup

{-# ANN validateMembers "HLint: ignore Eta reduce" #-}
-- | Make sure that the member declarations in a type definition
-- | Follow the pattern [<name> <type>, <name> <type>, ...]
-- | TODO: This function is only called by the deftype parts of the codebase, which is more specific than the following check implies.
validateMemberCases :: TypeEnv -> [Ty] -> [XObj] -> Either TypeError ()
validateMemberCases typeEnv typeVariables rest = mapM_ visit rest
  where visit (XObj (Arr membersXObjs) _ _) =
          validateMembers typeEnv typeVariables membersXObjs
        visit xobj =
          Left (InvalidSumtypeCase xobj)

validateMembers :: TypeEnv -> [Ty] -> [XObj] -> Either TypeError ()
validateMembers typeEnv typeVariables membersXObjs =
  if length membersXObjs `mod` 2 == 0
  then mapM_ (okXObjForType typeEnv typeVariables . snd) (pairwise membersXObjs)
  else Left (UnevenMembers membersXObjs)
validateOneCase _ XObj {} =
  error "Type members must be defined using array syntax: [member1 type1 member2 type2 ...]" -- | TODO: How to reach this case?

okXObjForType :: TypeEnv -> [Ty] -> XObj -> Either TypeError ()
okXObjForType typeEnv typeVariables xobj =
  case xobjToTy xobj of
    Just t -> canBeUsedAsMemberType typeEnv typeVariables t xobj
    Nothing -> Left (NotAType xobj)

-- | Can this type be used as a member for a deftype?
canBeUsedAsMemberType :: TypeEnv -> [Ty] -> Ty -> XObj -> Either TypeError ()
canBeUsedAsMemberType typeEnv typeVariables t xobj =
  case t of
    IntTy     -> return ()
    FloatTy   -> return ()
    DoubleTy  -> return ()
    ByteTy    -> return ()
    LongTy    -> return ()
    BoolTy    -> return ()
    StringTy  -> return ()
    PatternTy -> return ()
    CharTy    -> return ()
    FuncTy{} -> return ()
    PointerTy inner -> do _ <- canBeUsedAsMemberType typeEnv typeVariables inner xobj
                          return ()
    StructTy (ConcreteNameTy "Array") [inner] -> do _ <- canBeUsedAsMemberType typeEnv typeVariables inner xobj
                                                    return ()
    StructTy name [tyVars] ->
      case name of
        (ConcreteNameTy name') ->
          -- ensure structs are filled with values
          -- Prevents deftypes such as (deftype Player [pos Vector3])
          do _ <- canBeUsedAsMemberType typeEnv typeVariables tyVars xobj
             case lookupInEnv (SymPath [] name') (getTypeEnv typeEnv) of
               Just _ -> return ()
               Nothing -> Left (NotAmongRegisteredTypes t xobj)
        -- e.g. (deftype (Higher (f a)) (Of [(f a)]))
        t@(VarTy _) -> return ()
    s@(StructTy name tyvar) ->
      if isExternalType typeEnv s
      then return ()
      else case name of
             (ConcreteNameTy n) ->
               case lookupInEnv (SymPath [] n) (getTypeEnv typeEnv) of
                 Just (_, binder@(Binder _ xo@(XObj (Lst (XObj (Deftype t') _ _ : _))_ _))) ->
                   checkInhabitants t'
                 Just (_, binder@(Binder _ xo@(XObj (Lst (XObj (DefSumtype t') _ _ : _))_ _))) ->
                   checkInhabitants t'
                 _ -> Left (InvalidMemberType t xobj)
                 -- Make sure any struct types have arguments before they can be used as members.
                 where checkInhabitants ty =
                         case ty of
                         (StructTy _ vars) ->
                           if length vars == length tyvar
                           then return ()
                           else Left (UninhabitedConstructor ty xobj (length tyvar) (length vars))
                         _ -> Left (InvalidMemberType ty xobj)
             _ -> Left (InvalidMemberType t xobj)
    VarTy _ -> if t `elem` typeVariables
               then return ()
               else Left (InvalidMemberType t xobj)
    _ -> Left (InvalidMemberType t xobj)
