/// Presentation only: never use this value as a storage or credential key.
String azsignDisplayText(String value) => value
    .replaceAll('AZSignRemotePilot', 'AZSign Remote')
    .replaceAll('AZSign Remote Pilot', 'AZSign Remote')
    .replaceAll('AZSign Remote PoC', 'AZSign Remote');
