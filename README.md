# Zìgé · vocabolario HSK

Webapp per studiare il vocabolario HSK 2.0 e 3.0. Un singolo `index.html`
(HTML + CSS + JS vanilla, nessun framework), mobile-first, con tema
chiaro/scuro.

## Avvio in locale

Il `fetch` di `hsk.json` non funziona aprendo il file con doppio clic:
serve un server HTTP.

```bash
cd HSK
python3 -m http.server 8000
```

Poi apri <http://localhost:8000>.

Nessuna dipendenza da installare: serve solo Python 3 (già presente su
macOS) per il server e per la pipeline dati.

## Modalità

| Scheda | Cosa fa |
| --- | --- |
| Carte | ripetizione spaziata SM-2 con coda giornaliera e limite di parole nuove |
| Quiz | 10 domande a scelta multipla, tre varianti: hanzi → significato, significato → hanzi, ascolto → hanzi. I distrattori vengono dallo stesso livello della parola |
| Toni | 10 sillabe di una sola sillaba: ascolta e scegli il tono 1–4 |
| Scrivi | ordine dei tratti con Hanzi Writer: animazione, poi traccia tu nel 米字格 |
| Esame | 20 domande in 15 minuti, punteggio, revisione degli errori |
| Progressi | serie di giorni, parole nuove/in apprendimento/consolidate, ultimi 7 giorni, parole più sbagliate, record d'esame |

Tastiera su desktop: `spazio` gira la carta, `1`–`4` valutano o scelgono
l'opzione/tono/risposta d'esame.

## Rigenerare i dati

`hsk.json` è già generato e committato. Per rigenerarlo:

```bash
python3 build_data.py --download
```

Lo script scarica `complete.json` da
[drkameleon/complete-hsk-vocabulary](https://github.com/drkameleon/complete-hsk-vocabulary)
(la copia locale viene riusata se presente) e lo riduce a un file da ~1 MB
con 11.470 parole: hanzi semplificato e tradizionale, pinyin con diacritici
e numerazione dei toni, significato in inglese, livello HSK 2.0 e 3.0,
frequenza.

## Struttura

| File | Ruolo |
| --- | --- |
| `index.html` | tutta l'app: markup, stile e logica |
| `build_data.py` | genera `hsk.json` dalla sorgente |
| `hsk.json` | dizionario, caricato con `fetch` |
| `complete.json` | cache locale della sorgente (non è nel repository) |

I progressi stanno in `localStorage`; `hsk.json` e i dati dei tratti
visti nella scrittura vengono invece messi in cache su IndexedDB, così la
seconda visita non riscarica ~1 MB né i caratteri già disegnati.

## Note sui dati

- **Licenza della sorgente:** MIT, quindi redistribuibile. L'attribuzione è
  dentro `hsk.json` → `meta.source` e `meta.license`.
- **HSK 3.0:** il sillabo ufficiale raggruppa i livelli 7, 8 e 9 in una sola
  fascia, che qui è etichettata `7–9`. Non esiste una suddivisione ufficiale
  7/8/9 nei dati disponibili.
- **Frasi d'esempio: assenti.** La sorgente non ne contiene. Le alternative
  (Tatoeba, CC BY 2.0 FR; Gushi, CC BY-SA 4) richiederebbero attribuzioni
  aggiuntive o una licenza share-alike che propagherebbe sul resto.
- **Voce:** la sintesi vocale usa la Web Speech API del browser in `zh-CN`.
  Dipende dalle voci installate sul sistema, non da un file audio.

## Scrittura ed esame

**Scrittura.** La scheda mostra una parola dei livelli attivi (prima quelle
sbagliate nel quiz o nei toni), con pinyin, significato e una 米字格 per
carattere. «Guarda» anima l'ordine dei tratti, «Scrivi tu» avvia la prova:
il tratto va tracciato col dito o col mouse e Hanzi Writer corregge passo
passo.

Hanzi Writer non è incluso nella pagina: viene caricato da jsDelivr solo
quando apri la scheda. I dati dei singoli caratteri sono messi in IndexedDB,
quindi dopo il primo disegno la scrittura funziona anche senza rete (resta
necessario che il browser abbia in cache anche lo script della libreria).
I dati dei tratti derivano da [Make Me a Hanzi](https://github.com/skishore/makemeahanzi)
e sono distribuiti con licenza Arphic Public License; la libreria è MIT.
Marchi e licenze restano dei rispettivi autori.

**Esame.** 20 domande pescate a caso dai livelli attivi, 15 minuti, tre
varianti di domanda mescolate. Non c'è correzione durante la prova: alla
fine vedi punteggio, tempo impiegato, record e l'elenco delle parole
sbagliate con la risposta data. Le risposte mancate per tempo scaduto
contano come errori e finiscono comunque tra le parole da rivedere.

## Progressi e backup

La scheda **Progressi** conta solo i livelli attivi: serie di giorni
consecutivi, carte fatte oggi, parole nuove / in apprendimento /
consolidate (una carta passa a «consolidata» quando il suo intervallo
supera 21 giorni), attività degli ultimi sette giorni, cinque parole più
sbagliate con audio e record d'esame.

I progressi vivono in `localStorage` sotto `zige.progress.v1`. Due export
dalla stessa scheda:

- **JSON**: backup completo con intestazione (`app`, `version`,
  `exportedAt`, `progress`). L'import legge sia questo formato sia un
  `progress` senza intestazione, mostra un riepilogo e chiede conferma
  prima di sostituire i dati.
- **CSV per Anki**: una riga per parola già vista nel sillabo attivo,
  senza intestazione. Colonne: hanzi, `pinyin · significato`, tag del
  livello (es. `HSK3_L4`). I campi sono tra virgolette quando contengono
  virgole o virgolette; in Anki usa «virgola» come separatore e importa i
  tag dalla terza colonna.

## Ripetizione spaziata

Implementazione SM-2: intervallo 1 giorno alla prima ripetizione riuscita,
6 alla seconda, poi `intervallo × ease`. L'ease parte da 2.5, non scende
sotto 1.3. Valutare "Non so" azzera le ripetizioni e riporta la carta a
1 giorno.
