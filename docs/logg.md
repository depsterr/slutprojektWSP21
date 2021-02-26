# Log över arbete

# Fredag 29e januari

Idag så har jag skapat min DataBase klass, som sedan skapar databasens alla tables (om de inte finns), samt gjort några ändringar i mitt ER diagram. Har även skapat en generell projekt struktur samt börjat lite smått på några views och en helper.

# Fredag 5e februari

Idag så har jag skapat min Validator klass som validerar olika sorters input samt tar hand om timeouts för inloggningar. Jag har även lärt mig hur yardoc fungerar och dokumenterat Validator klassen och min tidigare DataBase klass med yardoc.

Jag fixade även flertalet ruby samt SQLite errors i min DataBase klass och nu funkar den som det ska.

# Fredag 12e februari

Idag så har jag jobbat vidare på min DataBase klass och implementerat metoderna log\_in register och delete\_user. Alla dessa filtrerar input och log\_in samt register har en fungerande timeout funktion. delete\_user kollar även om någon annan användare använder samma profilbild (min hemsida hashar varje bild och jämför hashes så samma profilbild bara lagras en gång), och om inte tar även bort filen från filsystemet och sedan databasen. Jag har även ommodellerat min databas till att använda `ON DELETE CASCADE` på vissa entiteter (t.ex posts i threads och threads i boards). Dock så har jag medvetet gjort så att inte boards, threads eller posts försvinner om användaren försvinner, för jag tänker att man skulle vilja ha kvar de även om användaren tar bort sitt konto eller blir avstängd.

Jag har även omstrukturerat mitt project efter en MVC metodologi, min app.rb är nu controller.rb, jag har placerat all konfiguration och andra strängar i views.rb (error strängar och forum namn) och jag har flyttat min DataBase och Validator klass in i model.rb.

Jag har även en liten lista på de andra CRUD metoder jag ska implementera i min DataBase class, varav de flesta är snabbare/lättare än de jag redan använt mig utav. Nästa lektion ska jag jobba mer med min model och implementera dessa, efter det ska jag bygga en sorts "API" med REST routes, efter detta ska jag skapa min "frontend" i form av slim filer.

# Fredag 26e februari

Idag så har jag implementerat databas metoder i min databas klass som klarar att skapa/ta bort boards, skapa/ta bort trådar och skapa/ta bort posts, stickiar threads, watchar och unwatchar threads, samt hämtar en lista av watchade threads.

Någon jag kommit på idag är att jag inte "sanitizar" min input för html tags, vilket gör min hemsida till ett potentiellt offer för xss (cross site scripting), det är alltså något jag borde fixa. Jag har även fixat så att min timout funktion tar bort alla gamla entries när den kallas, detta förhindrar den från att ta en väldigt massa minne om många användare använder sidan då och då.

Jag har även märkt att ON DELETE CASCADE inte fungerar... Så det får jag väl försöka fixa...

# Efter lektion 26e februari

Jag har nu listat ut vad som var felet med ON DELETE CASCADE. Det visade sig att SQLite inte stödjer foreign keys by default utan att det måste enablas med en så kallad pragma (inställning i sql typ), efter att ha sökt lite hittade jag att i python görs detta med `PRAGMA foreign_keys = ON;`, dock så fanns detta inte i ruby. Jag sökte då efter "ruby sqlite gem" på duckduckgo, kom till [denna](https://rubygems.org/gems/sqlite3) sida, där jag hittade en länk till [dokumentationen](https://www.rubydoc.info/gems/sqlite3/1.4.2). Här letade jag en del och hittade tillslut att under [DataBase klassen](https://www.rubydoc.info/gems/sqlite3/1.4.2/SQLite3/Database) finns det konstanter med namnet pragma. Efter att ha klickat mig dit kommer jag till [Pragmas klassen](https://www.rubydoc.info/gems/sqlite3/1.4.2/SQLite3/Pragmas). Dock verkar ingen metod finnas för att sätta på foreign keys (vad jag kan hitta). Men, det finns ett gäng [`set_<DATATYP>_pragma`](https://www.rubydoc.info/gems/sqlite3/1.4.2/SQLite3/Pragmas#set_boolean_pragma-instance_method) metoder som kan sätta en pragma från ett namn. Jag öppnar nu sqlite3 i min terminal och prövar skriva `PRAGMA foreign_keys;` och får tillbaka `0`. Alltså vill jag sätta en int pragma. Jag prövar då att sätta den till 1 och nu funkar foreign keys. Alltså behöver jag ha följande i min kod för att kunna använda min databas korrekt.
```rb
db.set_int_pragma("foreign_keys", 1)
```
Som tur är använder jag en separat klass för alla mina databas operationer, så detta är inte särskilt jobbigt då jag bara behöver lägga till denna rad på ett ställe.
