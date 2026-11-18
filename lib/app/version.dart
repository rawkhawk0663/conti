/// Version dieser Conti-Ausgabe, z. B. „v0.1.42“ – dieselbe Nummer wie beim
/// Download auf GitHub. Wird beim Bauen gesetzt (`--dart-define=CONTI_VERSION`).
const contiVersion = String.fromEnvironment('CONTI_VERSION', defaultValue: 'Testversion');
