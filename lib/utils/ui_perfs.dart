import 'package:shared_preferences/shared_preferences.dart';

enum TimeFormat { TWELVE_HOUR, TWENTY_FOUR_HOUR } // Corrected enum values

enum TemperatureUnit { CELSIUS, FAHRENHEIT } // Moved enum here

class UiPerfs {
  static final UiPerfs singleton = UiPerfs._internal();

  factory UiPerfs() {
    return singleton;
  }

  UiPerfs._internal();

  TemperatureUnit _temperatureUnit = TemperatureUnit.CELSIUS;
  TemperatureUnit get temperatureUnit => _temperatureUnit;
  set temperatureUnit(TemperatureUnit value) => _setTemperatureUnit(value);

  TimeFormat _timeFormat = TimeFormat.TWENTY_FOUR_HOUR;
  TimeFormat get timeFormat => _timeFormat;
  set timeFormat(TimeFormat value) => _setTimeFormat(value);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    // 0 = Celsius, 1 = Fahrenheit. Celsius is the default.
    final tempUnitIdx = prefs.getInt('temperatureUnit') ??
        TemperatureUnit.CELSIUS.index;
    _temperatureUnit = TemperatureUnit.values[tempUnitIdx];

    // 0 = 12-hour, 1 = 24-hour. 24-hour is the default.
    final timeFormatIdx = prefs.getInt('timeFormat') ??
        TimeFormat.TWENTY_FOUR_HOUR.index;
    _timeFormat = TimeFormat.values[timeFormatIdx];

    // Removed loading weather provider preference
  }

  void _setTemperatureUnit(TemperatureUnit value) async {
    final prefs = await SharedPreferences.getInstance();
    _temperatureUnit = value;
    prefs.setInt('temperatureUnit', value.index);
  }

  void _setTimeFormat(TimeFormat value) async {
    final prefs = await SharedPreferences.getInstance();
    _timeFormat = value;
    prefs.setInt('timeFormat', value.index);
  }

  // Removed _setWeatherProviderPackageName
}
