{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module Language.OWL2.Internal.Parser
  ( Parser
  , annotation
  , annotationProperty
  , annotationPropertyIRI
  , annotationValue
  , clazz
  , dataProperty
  , decimalLiteral
  , doubleOrMany
  , enclosedS
  , floatingPointLiteral
  , fullIRI
  , individual
  , initialState
  , integerLiteral
  , iri
  , lexeme
  , lexicalValue
  , listOfAtLeast2
  , namedIndividual
  , nodeID
  , nonEmptyList
  , nonNegativeInteger
  , objectProperty
  , ontologyIRI
  , optionalNegation
  , parens
  , prefixName
  , sc
  , singleOrMany
  , stringLiteralNoLanguage
  , stringLiteralWithLanguage
  , symbol
  , totalIRI
  , versionIRI
  , WithNegation(..)
  )
where

import           Data.Maybe                               ( fromMaybe )
import           Data.List.NonEmpty                       ( NonEmpty(..) )
import           Data.Void
import           Prelude                           hiding ( exponent )
import           Text.Megaparsec
import           Text.Megaparsec.Char
import qualified Text.Megaparsec.Char.Lexer    as L

import           Language.OWL2.Import                     ( Text )
import qualified Language.OWL2.Import          as T
import           Language.OWL2.Types

type Parser = Parsec Void Text

data WithNegation a
    = Positive a
    | Negative a deriving (Show)

-- | Parses white space and line comments
--
-- >>> parseTest (sc *> many (satisfy (const True))) "    some indented text"
-- "some indented text"
--
sc :: Parser ()
sc = L.space space1 (L.skipLineComment "#") empty

-- | Parses the actual lexeme and then any remaining space
--
lexeme :: Parser a -> Parser a
lexeme = L.lexeme sc

iriParens :: Parser a -> Parser a
iriParens = enclosed '<'

parens :: Parser a -> Parser a
parens = lexeme . enclosed '('

enclosed :: Char -> Parser a -> Parser a
enclosed c = between (char c >> sc) (char (cChar c))

enclosedS :: Char -> Parser a -> Parser a
enclosedS c = between (symbol . T.singleton $ c) (symbol . T.singleton . cChar $ c)

-- c for complement
cChar :: Char -> Char
cChar = \case
  '{' -> '}'
  '}' -> '{'
  '<' -> '>'
  '>' -> '<'
  '(' -> ')'
  ')' -> '('
  '[' -> ']'
  ']' -> '['
  c   -> c

-- | Parses the symbol and then any remaining space
--
-- >>> parseTest (symbol "a symbol" *> symbol "and a second") "a symbol    and a second"
-- "and a second"
--
symbol :: Text -> Parser Text
symbol = L.symbol sc

-- | It parses zero
--
-- >>> parseTest zero "0"
-- '0'
--
zero :: Parser Char
zero = char '0'

-- | It parses non positive integer
--
-- >>> parseTest nonZero "1"
-- '1'
--
nonZero :: Parser Char
nonZero = notFollowedBy zero *> digitChar

digit :: Parser Char
digit = zero <|> nonZero

digits :: Parser Text
digits = T.pack <$> some digit

-- | It parses positive integer
--
-- >>> parseTest positiveInteger "13"
-- 13
--
positiveInteger :: Parser Int
positiveInteger = do
  fd <- nonZero
  rm <- many digit
  lexeme . pure $ read (fd : rm)

-- | It parses non negativeinteger
--
-- >>> parseTest nonNegativeInteger "13"
-- 13
-- >>> parseTest nonNegativeInteger "0"
-- 0
--
nonNegativeInteger :: Parser Int
nonNegativeInteger =
  let num = (0 <$ zero) <|> positiveInteger
  in lexeme num

-- | It may parse a sign or no sign at all
--
-- >>> parseTest sign "+"
-- ""
-- >>> parseTest sign "-"
-- "-"
-- >>> parseTest sign ""
-- ""
--
sign :: Parser Text
sign = do
  mSign <- optional $ "" <$ symbol "+" <|> symbol "-"
  pure $ fromMaybe "" mSign

-- | It parses arbitrary alpharithmetics provived that it does not belong to
-- the list of reserved keywords
--
-- >>> parseTest identifier "label"
-- "label"
--
-- >>> parseTest identifier "label3With"
-- "label3With"
--
-- >>> parseTest identifier "label_3_With"
-- "label_3_With"
--
-- >>> parseTest identifier "1label"
-- ...
-- unexpected '1'
-- expecting letter
--
-- >>> parseTest identifier "Ontology"
-- ...
-- keyword "Ontology" cannot be an identifier
--
identifier :: Parser Text
identifier = lexeme identifier_

-- | It parses arbitrary alpharithmetics provived that it does not belong to
-- the list of reserved keywords. It does not parse any space after the identifier
--
identifier_ :: Parser Text
identifier_ = try (anyIdentifier_ >>= check)
 where
  check x =
    if x `elem` allKeywords
    then fail $ concat ["keyword ", show x, " cannot be an identifier"]
    else pure x

-- | It parses arbitrary alpharithmetics. It does not parse any space after the identifier
--
anyIdentifier_ :: Parser Text
anyIdentifier_ = T.pack <$> try ((:) <$> letterChar <*> many (alphaNumChar <|> char '_' <|> char '-'))

-- | It parses arbitrary alpharithmetics. It parses any space after the identifier
--
anyIdentifier :: Parser Text
anyIdentifier = lexeme anyIdentifier_

-- | It parses prefix names
--
-- >>> parseTest prefixName "owl:"
-- "owl"
--
-- >>> parseTest prefixName ":"
-- ""
--
-- >>> parseTest prefixName "owl    :"
-- ...
-- unexpected space
-- ...
--
prefixName :: Parser Text
prefixName = (identifier_ <|> pure "") <* string ":"

-- | TODO currently IRI is defined as text inside <>
-- No validation is being performed
-- Check: http://www.rfc-editor.org/rfc/rfc3987.txt for BNF representation
--
-- >>> parseTest fullIRI "<http://www.uom.gr/ai/TestOntology.owl#Child>"
-- FullIRI {_iriName = "http://www.uom.gr/ai/TestOntology.owl#Child"}
--
-- >>> parseTest fullIRI "<http://www.uom.gr/ai/TestOntology.owl#Child"
-- ...
-- unexpected end of input
-- expecting '>'
--
-- >>> parseTest fullIRI "http://www.uom.gr/ai/TestOntology.owl#Child"
-- ...
-- unexpected 'h'
-- expecting '<'
--
fullIRI :: Parser IRI
fullIRI = FullIRI <$> (lexeme . iriParens $ takeWhileP Nothing (/= '>'))

-- | It parses abbreviated IRIs. Format: 'prefix:term'
-- >>> parseTest abbreviatedIRI "xsd:string"
-- AbbreviatedIRI {_prefixName = "xsd", _prefixValue = "string"}
--
-- >>> parseTest abbreviatedIRI "owl:   user1"
-- ...
-- unexpected space
-- ...
--
abbreviatedIRI :: Parser IRI
abbreviatedIRI = AbbreviatedIRI <$> prefixName <*> anyIdentifier

-- | It parses simple IRIs; a finite sequence of characters matching the PN_LOCAL
-- production of [SPARQL] and not matching any of the keyword terminals of the syntax
--
-- TODO: Simplified to a simple identifier parser
-- >>> parseTest simpleIRI "John"
-- SimpleIRI {_simpleIRI = "John"}
--
simpleIRI :: Parser IRI
simpleIRI = SimpleIRI <$> identifier

-- | It parses any of the three different formats of IRIs
-- >>> parseTest iri "John"
-- SimpleIRI {_simpleIRI = "John"}
--
-- >>> parseTest iri "owl:John"
-- AbbreviatedIRI {_prefixName = "owl", _prefixValue = "John"}
--
-- >>> parseTest iri "<http://www.uom.gr/ai/TestOntology.owl#Child>"
-- FullIRI {_iriName = "http://www.uom.gr/ai/TestOntology.owl#Child"}
--
iri :: Parser IRI
iri = fullIRI <|> try abbreviatedIRI <|> try simpleIRI

ontologyIRI :: Parser IRI
ontologyIRI = iri

versionIRI :: Parser IRI
versionIRI = iri

clazz :: Parser ClassIRI
clazz = iri

objectProperty :: Parser ObjectPropertyIRI
objectProperty = iri

dataProperty :: Parser DataPropertyIRI
dataProperty = iri

annotationProperty :: Parser AnnotationPropertyIRI
annotationProperty = annotationPropertyIRI

-- | It parses an annotation property name. The annotation property can be either a IRI or an node id
--
-- >>> parseTest (totalIRI) "<http://example.com/ontology#name>"
-- NamedIRI {_namedIRI = FullIRI {_iriName = "http://example.com/ontology#name"}}
--
-- >>> parseTest (totalIRI) "_:randomNode"
-- AnonymousIRI {_nodeID = NodeID {_nLabel = "randomNode"}}
--
totalIRI :: Parser TotalIRI
totalIRI = AnonymousIRI <$> nodeID <|> NamedIRI <$> iri

annotationPropertyIRI :: Parser AnnotationPropertyIRI
annotationPropertyIRI = iri

-- | It parser node ids, iris or literals
-- TODO: Test should be ignored as the literal parser can vary
--
-- >> parseTest annotationTarget "\"john\""
-- LiteralAT (StringLiteralNoLang "john")
--
-- >> parseTest annotationTarget "John"
-- IriAT (SimpleIRI "John")
--
-- >> parseTest annotationTarget "_:node"
-- NodeAT (NodeID "node")
--
-- >> parseTest annotationTarget "<http://some.iri>"
-- IriAT (FullIRI "http://some.iri")
--
annotationValue :: Parser Literal -> Parser AnnotationValue
annotationValue l =  NodeAT    <$> try nodeID
                 <|> IriAT     <$> try iri
                 <|> LiteralAT <$> try l

-- | It parses a single annotation
-- TODO: Test should be ignored as the literal parser can vary
--
-- >> parseTest annotation ":creator \"john\""
-- Annotation (AnnotationProperty {unAnnotationProperty = AbbreviatedIRI "" "creator"}) (LiteralAT (StringLiteralNoLang "john"))
--
annotation :: Parser Literal -> Parser Annotation
annotation l = Annotation <$> annotationProperty <*> annotationValue l

-- | It parses blank nodes
--
-- >>> parseTest nodeID "_:blank"
-- NodeID {_nLabel = "blank"}
--
-- >>> parseTest nodeID ":blank"
-- ...
-- unexpected ":b"
-- expecting "_:"
--
-- >>> parseTest nodeID "blanknode"
-- ...
-- unexpected "bl"
-- expecting "_:"
--
nodeID :: Parser NodeID
nodeID = NodeID <$> (symbol "_:" *> identifier)

-- | It parses a string value with no language tag
--
-- >>> parseTest stringLiteralNoLanguage "\"hello there\""
-- "hello there"
--
stringLiteralNoLanguage :: Parser Text
stringLiteralNoLanguage = quotedString

-- | It parses a string value with language tag
--
-- >>> parseTest stringLiteralWithLanguage "\"hello there\"@en"
-- LiteralWithLang {_literalText = "hello there", _langTag = "en"}
--
stringLiteralWithLanguage :: Parser LiteralWithLang
stringLiteralWithLanguage = LiteralWithLang <$> quotedString <*> languageTag

-- | It parse a language tag
--
-- >>> parseTest languageTag "@en"
-- "en"
-- >>> parseTest languageTag "en"
-- ...
-- unexpected 'e'
-- expecting '@'
--
-- TODO: check for valid lang tags
languageTag :: Parser LangTag
languageTag = char '@' *> identifier_ -- (U+40) followed a nonempty sequence of characters matching the langtag production from [BCP 47]

-- | It parser decimal values
--
-- >>> parseTest decimalLiteral "10.345"
-- DecimalL {_dvalue = 10.345}
-- >>> parseTest decimalLiteral "-10.345"
-- DecimalL {_dvalue = -10.345}
-- >>> parseTest decimalLiteral "+10.345"
-- DecimalL {_dvalue = 10.345}
--
decimalLiteral :: Parser DecimalLiteral
decimalLiteral = do
  mSign <- sign
  dig1  <- digits
  dig2  <- symbol "." *> digits
  pure . DecimalL . read . T.unpack . T.concat $ [mSign, dig1, ".", dig2]

-- | It parser integer values
--
-- >>> parseTest integerLiteral "10"
-- IntegerL {_ivalue = 10}
-- >>> parseTest integerLiteral "-10"
-- IntegerL {_ivalue = -10}
-- >>> parseTest integerLiteral"+10"
-- IntegerL {_ivalue = 10}
--
integerLiteral :: Parser IntegerLiteral
integerLiteral = do
  mSign <- sign
  digs  <- digits
  pure . IntegerL . read . T.unpack $ mSign <> digs

-- | It parses a string enclosed in double quotes
--
-- >>> parseTest quotedString "\"this is a quoted string\""
-- "this is a quoted string"
-- >>> parseTest quotedString "\"this is \\\"test \\\" message\""
-- "this is \\\"test \\\" message"
--
-- >>> parseTest quotedString "\"text with\nnewlines\""
-- "text with\nnewlines"
--
quotedString :: Parser Text
quotedString = do
  strings <- char '\"' *> many chars <* char '\"'
  pure . T.pack . concat $ strings
 where
  chars     = (pure <$> nonEscape) <|> escape
  nonEscape = noneOf ("\\\"" :: String) -- all the characters that can be escaped
  escape    = do
    d <- char '\\'
    c <- oneOf ("\\\"0nrvtbf" :: String)
    pure [d, c]

-- | It parses folating point numbers.
-- Valid formats:
--   * 12F
--   * .3f
--   * 12.3f
--   * -12.3F
--
-- >>> parseTest floatingPointLiteral "12F"
-- FloatP {_floatValue = 12.0, _mExponent = Nothing}
-- >>> parseTest floatingPointLiteral "12.3f"
-- FloatP {_floatValue = 12.3, _mExponent = Nothing}
-- >>> parseTest floatingPointLiteral "-12.332F"
-- FloatP {_floatValue = -12.332, _mExponent = Nothing}
-- >>> parseTest floatingPointLiteral ".3f"
-- FloatP {_floatValue = 0.3, _mExponent = Nothing}
-- >>> parseTest floatingPointLiteral ".3e10f"
-- FloatP {_floatValue = 0.3, _mExponent = Just 10}
-- >>> parseTest floatingPointLiteral "-12.3e-10F"
-- FloatP {_floatValue = -12.3, _mExponent = Just (-10)}
--
floatingPointLiteral :: Parser FloatPoint
floatingPointLiteral = do
  sgn  <- sign
  dgts <- dig1 <|> dig2
  mExp <- optional exponent
  _    <- symbol "f" <|> symbol "F"
  pure $ FloatP (read . T.unpack $ sgn <> dgts) mExp
 where
  dig1 :: Parser Text
  dig1 = do
    dg'  <- digits
    mDec <- optional $ do
      dg <- symbol "." *> digits
      pure $ "." <> dg
    let dc = fromMaybe "" mDec
    pure $ dg' <> dc
  dig2 :: Parser Text
  dig2 = do
    dgts <- symbol "." *> digits
    pure $ "0." <> dgts


-- | It parses an exponent
--
-- >>> parseTest exponent "e10"
-- 10
-- >>> parseTest exponent "E10"
-- 10
-- >>> parseTest exponent "e+10"
-- 10
-- >>> parseTest exponent "E+10"
-- 10
-- >>> parseTest exponent "e-10"
-- -10
-- >>> parseTest exponent "E-10"
-- -10
--
exponent :: Parser Exponent
exponent = do
  _    <- symbol "e" <|> symbol "E"
  ms   <- sign
  dgts <- digits
  pure . read . T.unpack $ ms <> dgts

lexicalValue :: Parser Text
lexicalValue = quotedString

individual :: Parser TotalIRI
individual =  NamedIRI     <$> namedIndividual
          <|> AnonymousIRI <$> anonymousIndividual

namedIndividual :: Parser IndividualIRI
namedIndividual = iri

anonymousIndividual :: Parser NodeID
anonymousIndividual = nodeID

-- | Reserved keywords
allKeywords :: [Text]
allKeywords = concat [manchesterKeywords, functionalKeywords]

-- | Builds the initial state of a parser by setting:
--   - the name of the file to be parsed
--   - the line offset
--   - the column offset
--
--   This utility function is used by Quasi parsers where we need to set the 
--   offsets of the parser relative to the location of the text inside the source file
--
initialState :: (FilePath, Int, Int) -> s -> State s
initialState (filename, line, column) s = State
  { stateInput  = s
  , stateOffset = 0
  , statePosState = PosState
    { pstateInput = s
    , pstateOffset = 0
    , pstateSourcePos = SourcePos filename (mkPos line) (mkPos column)
    , pstateTabWidth = defaultTabWidth
    , pstateLinePrefix = ""
    }
  }


-----------------------
--- Generic parsers ---
-----------------------

optionalNegation :: Parser (WithNegation ())
optionalNegation = maybe (Positive ()) (const (Negative ())) <$> (optional . symbol $ "not")

-- | It parser one or more elements parsed by the input parser p and separated by the input string
--
-- >>> parseTest (singleOrMany "," . string $ "test") "test"
-- "test" :| []
--
-- >>> parseTest (singleOrMany "or" . lexeme . string $ "test") "test or test or test"
-- "test" :| ["test","test"]
--
-- >>> parseTest (singleOrMany "" identifier) "some  random text"
-- "some" :| ["random","text"]
--
singleOrMany :: Text -> Parser p -> Parser (NonEmpty p)
singleOrMany sep p =
  let multipleP = (:|) <$> p <*> some (symbol sep *> p) in try multipleP <|> (pure <$> p)

-- | It parses non empty lists
--
-- >>> parseTest (nonEmptyList languageTag) "@en, @el, @test"
-- "en" :| ["el","test"]
--
-- >>> parseTest (nonEmptyList languageTag) ""
-- ...
-- unexpected end of input
-- expecting '@'
--
nonEmptyList :: Parser p -> Parser (NonEmpty p)
nonEmptyList p = singleOrMany "," (lexeme p)
--nonEmptyList p = (:|) <$> lexeme p <*> many (symbol "," *> lexeme p)


-- | It parser two or more elements parsed by the input parser p and separated by the input string
--
-- >>> parseTest (doubleOrMany "" . string $ "test") "test"
-- ...
-- unexpected end of input
-- expecting "test"
--
-- >>> parseTest (doubleOrMany "" identifier) "some random"
-- ("some","random") :# []
--
-- >>> parseTest (doubleOrMany "" identifier) "some  random text"
-- ("some","random") :# ["text"]
--
doubleOrMany :: Text -> Parser p -> Parser (AtLeast2List p)
doubleOrMany sep p = atLeast2List' <$> p <*> (symbol sep *> singleOrMany sep p)

-- | It parses lists with at least two elements
--
-- >>> parseTest (listOfAtLeast2 languageTag) "@en, @el, @test"
-- ("en","el") :# ["test"]
--
-- >>> parseTest (listOfAtLeast2 languageTag) "@en"
-- ...
-- unexpected end of input
-- ...
--
listOfAtLeast2 :: Parser p -> Parser (AtLeast2List p)
listOfAtLeast2 = doubleOrMany "," -- atLeast2List' <$> p <*> (symbol "," *> nonEmptyList p)

manchesterKeywords :: [Text]
manchesterKeywords =
  [ "and"
  , "AnnotationProperty"
  , "Annotations"
  , "Asymmetric"
  , "Characteristics"
  , "Class"
  , "DataProperty"
  , "Datatype"
  , "decimal"
  , "DifferentFrom"
  , "DifferentIndividuals"
  , "DisjointClasses"
  , "DisjointProperties"
  , "DisjointProperties"
  , "DisjointUnionOf"
  , "DisjointWith"
  , "Domain"
  , "EquivalentClasses"
  , "EquivalentProperties"
  , "EquivalentProperties"
  , "EquivalentTo"
  , "Facts"
  , "float"
  , "Functional"
  , "HasKey"
  , "Import"
  , "Individual"
  , "integer"
  , "inverse"
  , "InverseFunctional"
  , "InverseOf"
  , "Irreflexive"
  , "length"
  , "maxLength"
  , "minLength"
  , "NamedInvividual"
  , "not"
  , "ObjectProperty"
  , "Ontology"
  , "or"
  , "pattern"
  , "Prefix"
  , "Range"
  , "Reflexive"
  , "SameAs"
  , "SameIndividual"
  , "string"
  , "SubClassOf"
  , "SubPropertyChain"
  , "SubPropertyOf"
  , "Symmetric"
  , "Transitive"
  , "Types"
  ]

functionalKeywords :: [Text]
functionalKeywords =
  [ "Annotation"
  , "AnnotationAssertion"
  , "AnnotationProperty"
  , "AnnotationPropertyDomain"
  , "AnnotationPropertyRange"
  , "AsymmetricObjectProperty"
  , "Class"
  , "ClassAssertion"
  , "DataAllValuesFrom"
  , "DataComplementOf"
  , "DataExactCardinality"
  , "DataHasValue"
  , "DataIntersectionOf"
  , "DataMaxCardinality"
  , "DataMinCardinality"
  , "DataOneOf"
  , "DataProperty"
  , "DataPropertyAssertion"
  , "DataPropertyDomain"
  , "DataPropertyRange"
  , "DataSomeValuesFrom"
  , "DataUnionOf"
  , "Datatype"
  , "DatatypeDefinition"
  , "DatatypeRestriction"
  , "Declaration"
  , "Declaration"
  , "DifferentIndividuals"
  , "DisjointClasses"
  , "DisjointDataProperties"
  , "DisjointObjectProperties"
  , "DisjointUnion"
  , "EquivalentClasses"
  , "EquivalentDataProperties"
  , "EquivalentObjectProperties"
  , "File parsed succesfully"
  , "FunctionalDataProperty"
  , "FunctionalObjectProperty"
  , "HasKey"
  , "Import"
  , "InverseFunctionalObjectProperty"
  , "InverseObjectProperties"
  , "IrreflexiveObjectProperty"
  , "NamedIndividual"
  , "NegativeDataPropertyAssertion"
  , "NegativeObjectPropertyAssertion"
  , "ObjectAllValuesFrom"
  , "ObjectComplementOf"
  , "ObjectExactCardinality"
  , "ObjectHasSelf"
  , "ObjectHasValue"
  , "ObjectIntersectionOf"
  , "ObjectInverseOf"
  , "ObjectMaxCardinality"
  , "ObjectMinCardinality"
  , "ObjectOneOf"
  , "ObjectProperty"
  , "ObjectPropertyAssertion"
  , "ObjectPropertyChain"
  , "ObjectPropertyDomain"
  , "ObjectPropertyRange"
  , "ObjectSomeValuesFrom"
  , "ObjectUnionOf"
  , "Ontology"
  , "Prefix"
  , "ReflexiveObjectProperty"
  , "SameIndividual"
  , "SubAnnotationPropertyOf"
  , "SubClassOf"
  , "SubDataPropertyOf"
  , "SubObjectPropertyOf"
  , "SymmetricObjectProperty"
  , "TransitiveObjectProperty"
  ]

