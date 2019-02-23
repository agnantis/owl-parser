{-# LANGUAGE OverloadedStrings #-}

module Language.OWL2.Functional.Parser where

import           Prelude                           hiding ( exponent )
import           Data.Functor                             ( ($>) )
import           Data.List.NonEmpty                       ( NonEmpty(..) )
import qualified Data.List.NonEmpty            as NE
import           Text.Megaparsec

import           Language.OWL2.Import                     ( Text )
import qualified Language.OWL2.Import          as T
import           Language.OWL2.Types               hiding (AnnList)

import           Language.OWL2.Internal.Parser

-- DocTest setup
--
-- $setup
-- >>> :set -XOverloadedStrings

--------------------------
-- Parser related types --
--------------------------

-- | It parses literals
--
-- >>> parseTest (literal *> eof) "\"32\"^^integer"
-- ...
-- unexpected '^'
-- ...
--
-- >>> parseTest (literal *> eof) "\"32\"^^xsd:integer"
-- ()
--
-- >>> parseTest (literal *> eof) "\"stringLiteralNoLanguage\""
-- ()
--
-- >>> parseTest (literal *> eof) "\"stringLiteralWithLang\"@en"
-- ()
--
literal :: Parser Literal
literal =  lexeme $ TypedLiteralC <$> try typedLiteral 
       <|> StringLiteralLang      <$> try stringLiteralWithLanguage
       <|> StringLiteralNoLang    <$> try stringLiteralNoLanguage

-- | It parses a typed literal
--
-- >>> parseTest typedLiteral "\"32\"^^integer"
-- ...
-- keyword "integer" cannot be an identifier
--
-- >>> parseTest (literal *> eof) "\"32\"^^xsd:integer"
-- ()
--
-- >>> parseTest (typedLiteral *> eof) "\"Jack\"^^xsd:string"
-- ()
--
typedLiteral :: Parser TypedLiteral
typedLiteral = TypedL <$> lexicalValue
                      <*> (symbol "^^" *> datatype)

ontologyDocument :: Parser ()
ontologyDocument = do
  many prefixDeclaration
  ontology
  pure ()

-- | It parses a prefix declaration
--
-- >>> parseTest (prefixDeclaration *> eof) "Prefix(owl:=<http://www.w3.org/2002/07/owl#>)"
-- ()
--
-- >>> parseTest (prefixDeclaration *> eof) "Prefix(:=<http://www.w3.org/2002/07/owl#>)"
-- ()
--
prefixDeclaration :: Parser PrefixDeclaration
prefixDeclaration = do
  symbol "Prefix"
  parens $ PrefixD <$> prefixName <*> (symbol "=" *> fullIRI)

ontology :: Parser ()
ontology = do
  symbol "Ontology"
  parens $ do
    optional $ do
      ontologyIRI
      try (optional versionIRI) -- Maybe (iri, Maybe iri)
    many directImport
    ontologyAnnotations
    axioms
  pure ()

-- | It parses import ontology declarations
--
-- >>> parseTest (directImport *> eof) "Import(<http://www.w3.org/2002/07/owl#>)"
-- ()
--
directImport :: Parser ImportDeclaration
directImport = ImportD <$> (symbol "Import" *> parens iri)

ontologyAnnotations :: Parser [Annotated Annotation]
ontologyAnnotations = fannotations

axioms :: Parser [()]
axioms = many axiom

-- | It parses  declarations
--
-- >>> parseTest (declaration *> eof) "Declaration(Class(<http://www.uom.gr/ai/TestOntology.owl#Child>))"
-- ()
--
declaration :: Parser ()
declaration = do
  symbol "Declaration"
  parens $ do
    axiomAnnotations
    entity
  pure ()

entity :: Parser Entity
entity =  EntityClass              <$> (symbol "Class"              *> parens clazz)
      <|> EntityDatatype           <$> (symbol "Datatype"           *> parens datatype)
      <|> EntityObjectProperty     <$> (symbol "ObjectProperty"     *> parens objectProperty)
      <|> EntityDataProperty       <$> (symbol "DataProperty"       *> parens dataProperty)
      <|> EntityAnnotationProperty <$> (symbol "AnnotationProperty" *> parens annotationProperty)
      <|> EntityIndividual         <$> (symbol "NamedIndividual"    *> parens namedIndividual)

axiomAnnotations :: Parser [Annotated Annotation]
axiomAnnotations = fannotations

newtype Annotated a = Annotated { unAnnotated :: ([Annotated Annotation], a) }

fannotation :: Parser (Annotated Annotation)
fannotation = do
  symbol "Annotation"
  parens $  do
     annots <- fannotations
     a      <- annotation literal
     pure $ Annotated (annots, a)

fannotations :: Parser [Annotated Annotation]
fannotations = many fannotation


annotationAnnotations :: Parser [Annotated Annotation]
annotationAnnotations = fannotations

annotationAxiom :: Parser ()
annotationAxiom =  annotationAssertion $> ()
               <|> subAnnotationPropertyOf $> ()
               <|> annotationPropertyDomain $> ()
               <|> annotationPropertyRange $> ()

annotationAssertion :: Parser ()
annotationAssertion = do
  symbol "AnnotationAssertion"
  parens $ do
    annots <- axiomAnnotations
    annotationProperty
    annotationSubject
    annotationTarget literal
  pure ()

annotationSubject :: Parser ()
annotationSubject = undefined

subAnnotationPropertyOf :: Parser (AnnotationProperty, AnnotationPropertyElement)
subAnnotationPropertyOf = do
  symbol "SubAnnotationPropertyOf"
  parens $ do
    annots   <- axiomAnnotations
    subAnn   <- subAnnotationProperty
    superAnn <- SubPropertyOfAPE <$> undefined -- superAnnotationProperty
    pure (subAnn, superAnn)

subAnnotationProperty :: Parser AnnotationProperty
subAnnotationProperty = annotationProperty

superAnnotationProperty :: Parser AnnotationProperty
superAnnotationProperty = annotationProperty

annotationPropertyDomain :: Parser ()
annotationPropertyDomain = do
  symbol "AnnotationPropertyDomain"
  parens $ do
    axiomAnnotations
    annotationProperty
    iri
  pure ()

annotationPropertyRange :: Parser ()
annotationPropertyRange = do
  symbol "AnnotationPropertyRange"
  parens $ do
    axiomAnnotations
    annotationProperty
    iri
  pure ()

datatype:: Parser Datatype
datatype = Datatype <$> iri

objectPropertyExpression :: Parser ()
objectPropertyExpression =  objectProperty $> ()
                        <|> inverseObjectProperty $> ()

inverseObjectProperty :: Parser ()
inverseObjectProperty = do
  symbol "ObjectInverseOf"
  parens objectProperty
  pure ()

dataPropertyExpression :: Parser DataProperty
dataPropertyExpression = dataProperty

dataRange :: Parser ()
dataRange =  datatype $> ()
         <|> dataIntersectionOf $> ()
         <|> dataUnionOf $> ()
         <|> dataComplementOf $> ()
         <|> dataOneOf $> ()
         <|> datatypeRestriction $> ()

dataIntersectionOf :: Parser ()
dataIntersectionOf = do
  symbol "DataIntersectionOf"
  parens $ do
    dataRange
    some dataRange
  pure ()

dataUnionOf :: Parser ()
dataUnionOf = do
  symbol "DataUnionOf"
  parens $ do
    dataRange
    some dataRange
  pure ()

dataComplementOf :: Parser ()
dataComplementOf = do
  symbol "DataComplementOf"
  parens dataRange
  pure ()

dataOneOf :: Parser ()
dataOneOf = do
  symbol "DataOneOf"
  parens $ some literal
  pure ()

datatypeRestriction :: Parser ()
datatypeRestriction = do
  symbol "DatatypeRestriction"
  parens $ do
    datatype
    constrainingFacet
    restrictionValue
    many $ do 
      constrainingFacet
      restrictionValue
  pure ()

constrainingFacet :: Parser IRI
constrainingFacet = iri

restrictionValue :: Parser Literal
restrictionValue = literal

classExpression :: Parser ()
classExpression = lexeme alternatives
 where
  alternatives =   objectOneOf $> ()
               <|> objectIntersectionOf $> ()
               <|> objectUnionOf $> ()
               <|> objectComplementOf $> ()
               <|> objectSomeValuesFrom $> ()
               <|> objectAllValuesFrom $> ()
               <|> objectHasValue $> ()
               <|> objectHasSelf $> ()
               <|> objectMinCardinality $> ()
               <|> objectMaxCardinality $> ()
               <|> objectExactCardinality $> ()
               <|> dataSomeValuesFrom $> ()
               <|> dataAllValuesFrom $> ()
               <|> dataHasValue $> ()
               <|> dataMinCardinality $> ()
               <|> dataMaxCardinality $> ()
               <|> dataExactCardinality$> ()
               <|> clazz $> ()


objectIntersectionOf :: Parser ()
objectIntersectionOf = do
  symbol "ObjectIntersectionOf"
  parens $ do
    classExpression
    some classExpression
  pure ()

objectUnionOf :: Parser ()
objectUnionOf = do
  symbol "ObjectUnionOf"
  parens $ do
    classExpression
    some classExpression
  pure ()

objectComplementOf :: Parser ()
objectComplementOf = do
  symbol "ObjectComplementOf"
  parens classExpression
  pure ()

objectOneOf :: Parser ()
objectOneOf = do
  symbol "ObjectOneOf"
  parens $ some individual
  pure ()

objectSomeValuesFrom :: Parser ()
objectSomeValuesFrom = do
  symbol "ObjectSomeValuesFrom"
  parens $ do
    objectPropertyExpression
    classExpression
  pure ()

objectAllValuesFrom :: Parser ()
objectAllValuesFrom = do
  symbol "ObjectAllValuesFrom"
  parens $ do
    objectPropertyExpression
    classExpression
  pure ()
    
objectHasValue :: Parser ()
objectHasValue = do
  symbol "ObjectHasValue"
  parens $ do
    objectPropertyExpression
    individual
  pure ()

objectHasSelf :: Parser ()
objectHasSelf = do
  symbol "ObjectHasSelf"
  parens objectPropertyExpression
  pure ()

objectCardinality :: Text -> Parser ()
objectCardinality l = do
  symbol l
  parens $ do
    nonNegativeInteger
    objectPropertyExpression
    optional classExpression
  pure ()

objectMinCardinality :: Parser ()
objectMinCardinality = objectCardinality "ObjectMinCardinality"

objectMaxCardinality :: Parser ()
objectMaxCardinality = objectCardinality "ObjectMaxCardinality"

objectExactCardinality :: Parser ()
objectExactCardinality = objectCardinality "ObjectExactCardinality"

dataSomeValuesFrom :: Parser ()
dataSomeValuesFrom = do
  symbol "DataSomeValuesFrom"
  parens $ do
    some dataPropertyExpression
    dataRange
  pure ()

dataAllValuesFrom :: Parser ()
dataAllValuesFrom = do
  symbol "DataAllValuesFrom"
  parens $ do
    some dataPropertyExpression
    dataRange
  pure ()

dataHasValue :: Parser ()
dataHasValue = do
  symbol "DataHasValue"
  parens $ do
    dataPropertyExpression
    literal
  pure ()

dataCardinality :: Text -> Parser ()
dataCardinality l = do
  symbol l
  parens $ do
    nonNegativeInteger
    dataPropertyExpression
    optional dataRange
  pure ()

dataMinCardinality :: Parser ()
dataMinCardinality = dataCardinality "DataMinCardinality"

dataMaxCardinality :: Parser ()
dataMaxCardinality = dataCardinality "DataMaxCardinality"

dataExactCardinality :: Parser ()
dataExactCardinality = dataCardinality "DataExactCardinality"

axiom :: Parser ()
axiom =  declaration $> ()
     <|> classAxiom $> ()
     <|> objectPropertyAxiom $> ()
     <|> dataPropertyAxiom $> ()
     <|> datatypeDefinition $> ()
     <|> hasKey $> ()
     <|> assertion $> ()
     <|> annotationAxiom $> ()

classAxiom :: Parser ()
classAxiom =  subClassOf $> ()
          <|> equivalentClasses $> ()
          <|> disjointClasses $> ()
          <|> disjointUnion $> ()

subClassOf :: Parser ()
subClassOf = do
  symbol "SubClassOf"
  parens $ do
    axiomAnnotations
    subClassExpression
    superClassExpression
  pure ()

subClassExpression :: Parser ()
subClassExpression = classExpression

superClassExpression :: Parser ()
superClassExpression = classExpression

equivalentClasses :: Parser ()
equivalentClasses = do
  symbol "EquivalentClasses"
  parens $ do
    axiomAnnotations
    classExpression
    some classExpression
  pure ()

disjointClasses :: Parser ()
disjointClasses = do
  symbol "DisjointClasses"
  parens $ do
    axiomAnnotations
    classExpression
    some classExpression
  pure ()

disjointUnion :: Parser ()
disjointUnion = do
  symbol "DisjointUnion"
  parens $ do
    axiomAnnotations
    clazz
    disjointClassExpressions
  pure ()

disjointClassExpressions :: Parser ()
disjointClassExpressions = do
  classExpression
  some classExpression
  pure ()

objectPropertyAxiom :: Parser ()
objectPropertyAxiom =  subObjectPropertyOf $> ()
                   <|> equivalentObjectProperties $> ()
                   <|> disjointObjectProperties $> ()
                   <|> inverseObjectProperties $> ()
                   <|> objectPropertyDomain $> ()
                   <|> objectPropertyRange $> ()
                   <|> functionalObjectProperty $> ()
                   <|> inverseFunctionalObjectProperty $> ()
                   <|> reflexiveObjectProperty $> ()
                   <|> irreflexiveObjectProperty $> ()
                   <|> symmetricObjectProperty $> ()
                   <|> asymmetricObjectProperty $> ()
                   <|> transitiveObjectProperty $> ()

subObjectPropertyOf :: Parser ()
subObjectPropertyOf = do
  symbol "SubObjectPropertyOf"
  parens $ do
    axiomAnnotations
    subObjectPropertyExpression
    superObjectPropertyExpression
  pure ()

subObjectPropertyExpression :: Parser ()
subObjectPropertyExpression =  objectPropertyExpression $> ()
                           <|> propertyExpressionChain $> ()

propertyExpressionChain :: Parser ()
propertyExpressionChain = do
  symbol "ObjectPropertyChain"
  parens $ do
    objectPropertyExpression
    some objectPropertyExpression
  pure ()

superObjectPropertyExpression :: Parser ()
superObjectPropertyExpression = objectPropertyExpression

equivalentObjectProperties :: Parser ()
equivalentObjectProperties = do
  symbol "EquivalentObjectProperties"
  parens $ do
    axiomAnnotations
    objectPropertyExpression
    some objectPropertyExpression
  pure ()

disjointObjectProperties :: Parser ()
disjointObjectProperties = do
  symbol "DisjointObjectProperties"
  parens $ do
    axiomAnnotations
    objectPropertyExpression
    some objectPropertyExpression
  pure ()

objectPropertyDomain :: Parser ()
objectPropertyDomain = do
  symbol "ObjectPropertyDomain"
  parens $ do
    axiomAnnotations
    objectPropertyExpression
    classExpression
  pure ()

objectPropertyRange :: Parser ()
objectPropertyRange = do
  symbol "ObjectPropertyRange"
  parens $ do
    axiomAnnotations
    objectPropertyExpression
    classExpression
  pure ()

inverseObjectProperties :: Parser ()
inverseObjectProperties = do
  symbol "InverseObjectProperties"
  parens $ do
    axiomAnnotations
    objectPropertyExpression
    objectPropertyExpression
  pure ()

genericObjectProperty :: Text -> Parser ()
genericObjectProperty p = do
  symbol p
  parens $ do
    axiomAnnotations
    objectPropertyExpression
  pure ()

functionalObjectProperty :: Parser ()
functionalObjectProperty = genericObjectProperty "FunctionalObjectProperty"

inverseFunctionalObjectProperty :: Parser ()
inverseFunctionalObjectProperty = genericObjectProperty "InverseFunctionalObjectProperty"

reflexiveObjectProperty :: Parser ()
reflexiveObjectProperty = genericObjectProperty "ReflexiveObjectProperty"

irreflexiveObjectProperty :: Parser ()
irreflexiveObjectProperty = genericObjectProperty "IrreflexiveObjectProperty"

symmetricObjectProperty :: Parser ()
symmetricObjectProperty = genericObjectProperty "SymmetricObjectProperty"

asymmetricObjectProperty :: Parser ()
asymmetricObjectProperty = genericObjectProperty "AsymmetricObjectProperty"

transitiveObjectProperty :: Parser ()
transitiveObjectProperty = genericObjectProperty "TransitiveObjectProperty"

dataPropertyAxiom :: Parser ()
dataPropertyAxiom =  subDataPropertyOf $> ()
                 <|> equivalentDataProperties $> ()
                 <|> disjointDataProperties $> ()
                 <|> dataPropertyDomain $> ()
                 <|> dataPropertyRange $> ()
                 <|> functionalDataProperty $> ()

subDataPropertyOf :: Parser ()
subDataPropertyOf = do
  symbol "SubDataPropertyOf"
  parens $ do
    axiomAnnotations
    subDataPropertyExpression
    superDataPropertyExpression
  pure ()

subDataPropertyExpression :: Parser DataProperty
subDataPropertyExpression = dataPropertyExpression

superDataPropertyExpression :: Parser DataProperty
superDataPropertyExpression = dataPropertyExpression

equivalentDataProperties :: Parser ()
equivalentDataProperties = do
  symbol "EquivalentDataProperties"
  parens $ do
    axiomAnnotations
    dataPropertyExpression
    some dataPropertyExpression
  pure ()

disjointDataProperties :: Parser ()
disjointDataProperties = do
  symbol "DisjointDataProperties"
  parens $ do
    axiomAnnotations
    dataPropertyExpression
    some dataPropertyExpression
  pure ()

dataPropertyDomain :: Parser ()
dataPropertyDomain = do
  symbol "DataPropertyDomain"
  parens $ do
    axiomAnnotations
    dataPropertyExpression
    classExpression
  pure ()

dataPropertyRange :: Parser ()
dataPropertyRange = do
  symbol "DataPropertyRange"
  parens $ do
    axiomAnnotations
    dataPropertyExpression
    dataRange
  pure ()

functionalDataProperty :: Parser ()
functionalDataProperty = do
  symbol "FunctionalDataProperty"
  parens $ do
    axiomAnnotations
    dataPropertyExpression
  pure ()

datatypeDefinition :: Parser ()
datatypeDefinition = do
  symbol "DatatypeDefinition"
  parens $ do
    axiomAnnotations
    datatype
    dataRange
  pure ()

hasKey :: Parser ()
hasKey = do
  symbol "HasKey"
  parens $ do
    axiomAnnotations
    classExpression
    parens $ many objectPropertyExpression
    parens $ many dataPropertyExpression
  pure ()

assertion :: Parser ()
assertion =  sameIndividual $> ()
         <|> differentIndividuals $> ()
         <|> classAssertion $> ()
         <|> objectPropertyAssertion $> ()
         <|> negativeObjectPropertyAssertion $> ()
         <|> dataPropertyAssertion $> ()
         <|> negativeDataPropertyAssertion $> ()

sourceIndividual :: Parser Individual
sourceIndividual = individual

targetIndividual :: Parser Individual
targetIndividual = individual

targetValue :: Parser Literal
targetValue = literal

sameIndividual :: Parser ()
sameIndividual = do
  symbol "SameIndividual"
  parens $ do
    axiomAnnotations
    individual
    some individual
  pure ()

differentIndividuals :: Parser ()
differentIndividuals = do
  symbol "DifferentIndividuals"
  parens $ do
    axiomAnnotations
    individual
    some individual
  pure ()

classAssertion :: Parser ()
classAssertion = do
  symbol "ClassAssertion"
  parens $ do
    axiomAnnotations
    classExpression
    individual
  pure ()

objectPropertyAssertion :: Parser ()
objectPropertyAssertion = do
  symbol "ObjectPropertyAssertion"
  parens $ do
    axiomAnnotations
    objectPropertyExpression
    sourceIndividual
    targetIndividual
  pure ()

negativeObjectPropertyAssertion :: Parser ()
negativeObjectPropertyAssertion = do
  symbol "NegativeObjectPropertyAssertion"
  parens $ do
    axiomAnnotations
    objectPropertyExpression
    sourceIndividual
    targetIndividual
  pure ()

dataPropertyAssertion :: Parser ()
dataPropertyAssertion = do
  symbol "DataPropertyAssertion"
  parens $ do
    axiomAnnotations
    dataPropertyExpression
    sourceIndividual
    targetValue
  pure ()

negativeDataPropertyAssertion :: Parser ()
negativeDataPropertyAssertion = do
  symbol "NegativeDataPropertyAssertion"
  parens $ do
    axiomAnnotations
    dataPropertyExpression
    sourceIndividual
    targetIndividual
  pure ()


parseOntologyDoc :: FilePath -> IO (Maybe ())
parseOntologyDoc file =
  putStrLn ("Parsing ontology document: '" <> file <> "'") >>
  T.readFile file >>= parseContent
  where
    parseContent content =
      case parse (ontologyDocument <* eof) file content of
        Left bundle -> do
          putStrLn "Unable to parse file. Reason: "
          putStrLn (errorBundlePretty bundle)
          pure Nothing
        Right doc -> do
          putStrLn "File parsed succesfully"
          pure (Just ())

