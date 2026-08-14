import Foundation

public extension SourceLanguage {
    /// Danish, as data.
    ///
    /// Everything here was previously spelled out inside whichever service
    /// happened to need it — the abbreviations in the sentence boundary, the
    /// closed classes in the translation quality service, the beginner glosses
    /// in their own service, æøå in the OCR language policy. Collected in one
    /// value, a second language is a second file rather than a search.
    static let danish = SourceLanguage(
        code: "da",
        displayName: "Danish",
        localeIdentifier: "da_DK",
        speechVoice: "da-DK",
        letterFoldings: ["æ": "ae", "ø": "oe", "å": "aa"],
        ocr: OCRLanguageHints(
            recognitionLanguages: ["da-DK", "da"],
            tesseractCode: "dan",
            // Short price and commerce phrases are often classified as another
            // language even when they are Danish, so a distinctive letter is
            // allowed to override the classifier outright.
            distinctiveCharacters: CharacterSet(charactersIn: "æøåÆØÅ")
        ),
        sentenceRules: SentenceBoundaryRules(
            // A period is a weak signal in Danish. Ordinals carry one — "den
            // 15. september" — dates and list numbers carry one, and the
            // language abbreviates heavily.
            abbreviations: [
                "adm", "afd", "alm", "ang", "bl", "bl.a", "ca", "cf", "d",
                "dvs", "e.kr", "eftm", "ekskl", "el", "etc", "evt", "f",
                "f.eks", "f.kr", "fhv", "fr", "fx", "hhv", "hr", "iflg",
                "ift", "inkl", "jf", "jf.fx", "kl", "kr", "lign", "m.fl",
                "m.m", "maks", "mdr", "mht", "min", "mio", "mia", "mfl",
                "mm", "nr", "osv", "pct", "pga", "pkt", "prof", "red",
                "resp", "s", "sek", "st", "stk", "tlf", "th", "tv", "vedr"
            ]
        ),
        closedClassGlosses: Self.danishClosedClassGlosses,
        // Context-free translation occasionally turns the very common Danish
        // preposition "for" into "no". These are the useful English readings a
        // single-word bridge may safely present.
        acceptedGlosses: [
            "for": ["for", "too", "because", "ago"]
        ],
        exactGlosses: [
            "avanceret": "advanced",
            "arkitektur": "architecture",
            "computer": "computer",
            "data": "data",
            "database": "database",
            "databaser": "databases",
            "for": "for",
            "netvaerk": "network",
            "orkestrering": "orchestration",
            "software": "software",
            "teknologi": "technology",
            "telemedicin": "telemedicine",
            "udvikling": "development",
            "web": "web",
            "webarkitektur": "web architecture"
        ],
        compoundSuffixes: [
            CompoundSuffix(suffix: "arkitektur", gloss: "architecture"),
            CompoundSuffix(suffix: "orkestrering", gloss: "orchestration"),
            CompoundSuffix(suffix: "telemedicin", gloss: "telemedicine"),
            CompoundSuffix(suffix: "teknologi", gloss: "technology"),
            CompoundSuffix(suffix: "udvikling", gloss: "development"),
            CompoundSuffix(suffix: "databaser", gloss: "databases"),
            CompoundSuffix(suffix: "database", gloss: "database"),
            CompoundSuffix(suffix: "netvaerk", gloss: "network"),
            CompoundSuffix(suffix: "systemer", gloss: "systems"),
            CompoundSuffix(suffix: "system", gloss: "system")
        ],
        beginnerGlosses: Self.danishBeginnerGlosses,
        vacuousExplanations: [
            "betyder",
            "det betyder",
            "ordet betyder"
        ],
        structuralWords: [
            "ad", "af", "at", "da", "de", "den", "der", "det", "du",
            "eller", "en", "end", "er", "et", "for", "fordi", "fra",
            "han", "har", "hun", "hvad", "hvem", "hvor", "hvis", "i",
            "ikke", "jeg", "kan", "med", "men", "mod", "når", "og",
            "om", "på", "sig", "sin", "sit", "skal", "som", "til",
            "var", "ved", "vi", "vil"
        ],
        meansPhrase: { meaning in "Betyder “\(meaning)”." }
    )

    /// Danish's closed classes, in the folded ASCII form `folded` produces.
    ///
    /// A preposition has no single English equivalent — "på" is on, at, or in
    /// depending on what follows — so these are citation forms, right often
    /// rather than always. That is still a different order of accuracy from
    /// what a sentence-trained model returns for a word handed to it alone.
    private static let danishClosedClassGlosses: [String: String] = [
        // Copula, auxiliaries, and modals
        "er": "is", "var": "was", "vaeret": "been", "vaere": "be",
        "har": "has", "havde": "had", "haft": "had",
        "blive": "become", "bliver": "becomes", "blev": "became",
        "blevet": "become", "kan": "can", "kunne": "could",
        "skal": "must", "skulle": "should", "vil": "will",
        "ville": "would", "maa": "may", "maatte": "had to", "boer": "should",
        // Articles and determiners
        "en": "a", "et": "a", "den": "the", "det": "it", "de": "they",
        "denne": "this", "dette": "this", "disse": "these",
        // Conjunctions and subordinators
        "og": "and", "eller": "or", "men": "but", "som": "which",
        "at": "that", "naar": "when", "da": "when", "hvis": "if",
        "fordi": "because", "mens": "while", "end": "than",
        "baade": "both", "samt": "and",
        // Prepositions
        "i": "in", "paa": "on", "til": "to", "af": "of", "for": "for",
        "med": "with", "om": "about", "ved": "at", "fra": "from",
        "over": "over", "under": "under", "efter": "after",
        "foer": "before", "mod": "towards", "hos": "with",
        "uden": "without", "mellem": "between", "gennem": "through",
        "omkring": "around", "ind": "in", "ud": "out",
        // Pronouns and possessives
        "jeg": "I", "du": "you", "han": "he", "hun": "she", "vi": "we",
        "dig": "you", "mig": "me", "sig": "itself", "os": "us",
        "jer": "you", "dem": "them", "min": "my", "mit": "my",
        "din": "your", "dit": "your", "sin": "its", "sit": "its",
        "vores": "our", "deres": "their", "hans": "his",
        "hendes": "her", "man": "one", "der": "there", "hvad": "what",
        "hvem": "who", "hvor": "where", "hvilken": "which",
        "ikke": "not"
    ]

    private static let danishBeginnerGlosses: [String: String] = [
        "og": "Binder to ting eller sætninger sammen.",
        "eller": "Viser, at der er et valg mellem flere muligheder.",
        "men": "Viser en forskel eller noget uventet.",
        "fordi": "Fortæller grunden til noget.",
        "hvis": "Viser, at noget kun sker under en bestemt betingelse.",
        "som": "Binder en beskrivelse sammen med en person eller ting.",
        "der": "Peger på et sted eller starter en beskrivelse.",
        "det": "Bruges om en ting, idé eller situation.",
        "den": "Bruges om en bestemt person eller ting.",
        "de": "Bruges om flere personer eller ting.",
        "en": "En ubestemt artikel foran et navneord.",
        "et": "En ubestemt artikel foran et intetkønsord.",
        "at": "Står ofte foran et udsagnsord i grundform.",
        "er": "Nutid af at være.",
        "var": "Datid af at være.",
        "være": "At eksistere eller befinde sig i en bestemt tilstand.",
        "har": "Nutid af at have.",
        "have": "At eje, få eller opleve noget.",
        "kan": "Har mulighed eller evne til at gøre noget.",
        "kunne": "Datid eller en høflig form af kan.",
        "skal": "Viser en plan, pligt eller noget, der kommer til at ske.",
        "vil": "Viser et ønske eller noget, der kommer til at ske.",
        "må": "Har lov til eller er nødt til at gøre noget.",
        "gøre": "At udføre en handling.",
        "går": "Bevæger sig til fods eller fungerer på en bestemt måde.",
        "gå": "At bevæge sig til fods.",
        "kommer": "Bevæger sig hen til et sted.",
        "komme": "At bevæge sig hen til et sted.",
        "se": "At bruge øjnene eller forstå noget.",
        "sige": "At udtrykke noget med ord.",
        "tale": "At bruge stemmen til at kommunikere.",
        "læse": "At forstå skrevne ord.",
        "lære": "At få ny viden eller en ny færdighed.",
        "skrive": "At lave ord og sætninger med bogstaver.",
        "arbejde": "At udføre opgaver, ofte som en del af et job.",
        "bo": "At have sit hjem et bestemt sted.",
        "spise": "At tage mad ind i kroppen.",
        "drikke": "At tage væske ind i kroppen.",
        "dag": "Tiden fra morgen til aften; også et døgn.",
        "tid": "Det, vi måler i sekunder, timer, dage og år.",
        "år": "En periode på tolv måneder.",
        "menneske": "En person; et medlem af menneskearten.",
        "person": "Et enkelt menneske.",
        "barn": "En ung person, som endnu ikke er voksen.",
        "familie": "Personer, der er i familie eller lever tæt sammen.",
        "hjem": "Det sted, hvor en person bor og føler sig hjemme.",
        "hus": "En bygning, som mennesker kan bo i.",
        "skole": "Et sted, hvor mennesker underviser og lærer.",
        "studiebolig": "En bolig, der er lavet til en studerende.",
        "studieboliger": "Boliger, der er lavet til studerende.",
        "studentbolig": "En bolig, der er lavet til en studerende.",
        "studentboliger": "Boliger, der er lavet til studerende.",
        "kursus": "Et forløb, hvor man lærer om et bestemt emne.",
        "kurser": "Flertal af kursus: flere læringsforløb.",
        "ord": "En del af et sprog med en bestemt betydning.",
        "sprog": "Et system af ord og regler, som mennesker kommunikerer med.",
        "dansk": "Det sprog, man hovedsageligt taler i Danmark.",
        "engelsk": "Et sprog, der tales i blandt andet Storbritannien og USA.",
        "danmark": "Et land i Nordeuropa med dansk som hovedsprog.",
        "vej": "Et sted, man bevæger sig ad for at komme frem.",
        "række": "Flere ting efter hinanden; kan også betyde at nå.",
        "mere": "En større mængde eller grad.",
        "også": "Fortæller, at noget gælder i tillæg til noget andet.",
        "her": "På dette sted.",
        "hvor": "Spørger om eller viser et sted.",
        "hvordan": "Spørger om måden, noget sker eller gøres på.",
        "hvorfor": "Spørger om grunden til noget.",
        "hvad": "Spørger om en ting, handling eller idé.",
        "hvem": "Spørger om en person.",
        "hvornår": "Spørger om et tidspunkt.",
        "tilbyder": "Giver nogen mulighed for at få eller bruge noget.",
        "passer": "Er rigtig eller egnet til en person eller situation.",
        "tilmelde": "At skrive sig op som deltager.",
        "online": "Forbundet med eller tilgængelig gennem internettet."
    ]
}

public extension TargetLanguage {
    static let english = TargetLanguage(
        code: "en",
        displayName: "English",
        localeIdentifier: "en_GB",
        speechVoice: "en-GB",
        danglingWords: [
            "a", "am", "an", "and", "are", "as", "at", "be", "been",
            "being", "by", "for", "from", "in", "is", "of", "or", "that",
            "the", "to", "was", "were", "with"
        ],
        hasSystemDictionary: true
    )
}

public extension LanguagePair {
    /// What the app ships reading today.
    static let danishToEnglish = LanguagePair(
        source: .danish,
        target: .english
    )
}
