import Foundation

struct BeginnerDanishService {
    func localExplanation(for word: String) -> String? {
        Self.explanations[Self.normalized(word)]
    }

    func clean(explanation: String) -> String {
        let compact = explanation
            .replacingOccurrences(
                of: "\\s+",
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else {
            return ""
        }

        let limited: String
        if compact.count > 220 {
            let end = compact.index(
                compact.startIndex,
                offsetBy: 220
            )
            limited = String(compact[..<end])
                .trimmingCharacters(in: .whitespaces)
                + "…"
        } else {
            limited = compact
        }

        if limited.hasSuffix(".")
            || limited.hasSuffix("!")
            || limited.hasSuffix("?")
            || limited.hasSuffix("…") {
            return limited
        }
        return limited + "."
    }

    private static func normalized(_ word: String) -> String {
        word.lowercased()
            .trimmingCharacters(
                in: CharacterSet.whitespacesAndNewlines
                    .union(.punctuationCharacters)
            )
    }

    /// Hand-written hints cover frequent function words where a general
    /// dictionary definition is usually less useful to a new learner.
    private static let explanations: [String: String] = [
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
        "er": "Nutid af “at være”.",
        "var": "Datid af “at være”.",
        "være": "At eksistere eller befinde sig i en bestemt tilstand.",
        "har": "Nutid af “at have”.",
        "have": "At eje, få eller opleve noget.",
        "kan": "Har mulighed eller evne til at gøre noget.",
        "kunne": "Datid eller en høflig form af “kan”.",
        "skal": "Viser en plan, pligt eller noget, der kommer til at ske.",
        "vil": "Viser et ønske eller noget, der kommer til at ske.",
        "må": "Har lov til eller er nødt til at gøre noget.",
        "gøre": "At udføre en handling.",
        "går": "Bevæger sig til fods eller fungerer på en bestemt måde.",
        "gå": "At bevæge sig til fods.",
        "kommer": "Bevæger sig hen til et sted.",
        "komme": "At bevæge sig hen til et sted.",
        "kommet": "En form af “at komme”; nogen er nået frem.",
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
        "kursus": "Et forløb, hvor man lærer om et bestemt emne.",
        "kurser": "Flertal af “kursus”: flere læringsforløb.",
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
