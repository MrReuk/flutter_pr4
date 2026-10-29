const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8080/api',
);

/// Секунд без действий пользователя до выхода (по умолчанию три минуты).
const inactivitySeconds = int.fromEnvironment('INACTIVITY_SECONDS', defaultValue: 180);

/// За сколько секунд до выхода показывать предупреждение.
const inactivityWarningSeconds = int.fromEnvironment(
  'INACTIVITY_WARNING_SECONDS',
  defaultValue: 30,
);

/// Предельная длительность сессии в минутах независимо от активности.
const maxSessionMinutes = int.fromEnvironment('SESSION_MAX_MINUTES', defaultValue: 480);
