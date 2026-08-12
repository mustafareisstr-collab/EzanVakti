import 'dart:convert';
import 'package:dini_atlas/models/location_api/city.dart';
import 'package:dini_atlas/models/location_api/country.dart';
import 'package:dini_atlas/models/location_api/state.dart';
import 'package:dini_atlas/models/prayer/eid_prayer.dart';
import 'package:dini_atlas/models/prayer/prayer_time.dart';
import 'package:dini_atlas/models/prayer/prayer_times.dart';
import 'package:dini_atlas/models/religious_days.dart';
import 'package:dini_atlas/models/user_location.dart';
import 'package:dini_atlas/models/user_setting.dart';
import 'package:dini_atlas/services/local/prayer_times_service.dart';
import 'package:dini_atlas/services/local/user_settings_service.dart';
import 'package:dini_atlas/app/app.locator.dart';
import 'package:dini_atlas/ui/common/constants/constants.dart';
import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';

import 'dio_service.dart';

class FetchTimesException implements Exception {
  final String message;
  FetchTimesException(this.message);
}

class FetchTimesService {
  final _userSettings = locator<UserSettingsService>();
  final _prayerTimesService = locator<PrayerTimesService>();
  final _dio = locator<DioService>();

  final String _baseUrl = "https://ezanvakti.com/api";
  final String _countryUrl = "ulkeler";
  final String _cityUrl = "sehirler";
  final String _stateUrl = "ilceler";
  final String _timesUrl = "vakitler";
  final String _eidTimesUrl = "bayram-namazi";
  final String _religiousDaysUrl = "/dinigunler";

  Future<Either<PrayerTimes, FetchTimesException>> fetchTimes(
      {UserLocation? userLocation}) async {
    try {
      UserSettings? userSettings = await _userSettings.getUserSettings();

      if (userSettings == null) {
        throw UserSettingsException("Kullanıcıya ait kayıtlı ayar bulunamadı.");
      }

      bool dontFetchTimes = false;

      if (userSettings.city == null) {
        final values = await _getLocationIds(
            UserLocation.fromIsarJson(userSettings.jsonString));
        userSettings
          ..city = values.city
          ..state = values.state;
      } else {
        if (userLocation != null) {
          final String oldLocation = userSettings.jsonString;
          final String newLocation = jsonEncode(userLocation.toJson());

          if (oldLocation != newLocation) {
            final values = await _getLocationIds(userLocation);
            userSettings
              ..city = values.city
              ..state = values.state;
          } else {
            dontFetchTimes = true;
          }
        }
      }

      if (!dontFetchTimes) {
        final prayerTimes = await _fetchPrayerTimes(userSettings);
        await _prayerTimesService.setPrayerTimes(prayerTimes);
        return Left(prayerTimes);
      }
      return Right(FetchTimesException("Vakitler alınırken sorun oluştu"));
    } catch (e) {
      return Right(FetchTimesException(e.toString()));
    }
  }

  Future<PrayerTimes> _fetchPrayerTimes(UserSettings userSetting) async {
    try {
      final List<PrayerTime> times = await _getTimes(userSetting.state!.ilceId);
      final EidPrayerTime eidTimes =
          await _getEidTimes(userSetting.city!, userSetting.state!.ilceId);

      final prayerTimes = PrayerTimes()
        ..prayerTimes = times
        ..eidPrayers = eidTimes
        ..lastFetch = DateTime.now();

      return prayerTimes;
    } catch (e) {
      rethrow;
    }
  }

  Future<PrayerTimes?> updateAndGetTimes() async {
    try {
      await fetchTimes();
      final result = await _prayerTimesService.getPrayerTimes();
      return result.fold((l) => l, (r) => null);
    } catch (e) {
      throw PrayerTimesException(e.toString());
    }
  }

  Future<({City city, StateModel state})> _getLocationIds(
    UserLocation userLocation,
  ) async {
    try {
      final Country country = await _getUserCountry(userLocation.country);
      final City city = await _getUserCity(userLocation.city, country);
      final StateModel state = await _getUserState(
          userLocation.city, userLocation.state, city.sehirId);

      await _userSettings.setUserLocationSettings(
          country: country, city: city, state: state, location: userLocation);

      return (city: city, state: state);
    } catch (e) {
      debugPrint("Lokasyon Id'leri alınırken sorun oluştu");
      rethrow;
    }
  }

  Future<List<Country>> getCountries() async {
    final response = await _dio.request("$_baseUrl/$_countryUrl");

    if (response == null || response.statusCode != 200) {
      throw FetchTimesException("Ülke bilgisi getirilirken sorun oluştu.");
    }

    final List<Country> countries =
        (response.data as List).map((e) => Country.fromJson(e)).toList();
    return countries;
  }

  Future<Country> _getUserCountry(String country) async {
    try {
      final countries = await getCountries();
      return countries.singleWhere(
        (e) => e.ulkeAdi == country || e.ulkeAdiEn == country,
      );
    } catch (e) {
      debugPrint("Ülke bilgisi alınırken sorun oluştu");
      rethrow;
    }
  }

  Future<List<City>> getCities(String countryId) async {
    final response = await _dio.request("$_baseUrl/$_cityUrl/$countryId");

    if (response == null || response.statusCode != 200) {
      throw FetchTimesException("Şehir bilgisi getirilirken sorun oluştu.");
    }

    final List<City> cities =
        (response.data as List).map((e) => City.fromJson(e)).toList();
    return cities;
  }

  Future<City> _getUserCity(String city, Country country) async {
    try {
      final cities = await getCities(country.ulkeId);
      int foundIndex = cities.indexWhere(
        (e) => e.sehirAdi == city || e.sehirAdiEn == city,
      );

      if (foundIndex == -1) {
        foundIndex = cities.indexWhere(
          (e) =>
              e.sehirAdi == country.ulkeAdiEn ||
              e.sehirAdiEn == country.ulkeAdiEn ||
              e.sehirAdi == country.ulkeAdi,
        );
      }

      return cities[foundIndex];
    } catch (e) {
      debugPrint("Şehir bilgisi alınırken sorun oluştu: $city");
      rethrow;
    }
  }

  Future<List<StateModel>> getStates(String cityId) async {
    final response = await _dio.request("$_baseUrl/$_stateUrl/$cityId");

    if (response == null || response.statusCode != 200) {
      throw FetchTimesException("İlçe bilgisi getirilirken sorun oluştu.");
    }

    final List<StateModel> states =
        (response.data as List).map((e) => StateModel.fromJson(e)).toList();
    return states;
  }

  Future<StateModel> _getUserState(
      String city, String state, String cityId) async {
    try {
      final states = await getStates(cityId);
      int foundIndex = states.indexWhere(
        (e) => e.ilceAdi == state || e.ilceAdiEn == state,
      );
      if (foundIndex == -1) {
        foundIndex = states.indexWhere(
          (e) => e.ilceAdi == city || e.ilceAdiEn == city,
        );
      }
      return states[foundIndex];
    } catch (e) {
      debugPrint("İlçe bilgisi alınırken sorun oluştu: $state");
      rethrow;
    }
  }

  Future<List<PrayerTime>> _getTimes(String stateId) async {
    try {
      final response = await _dio.request("$_baseUrl/$_timesUrl/$stateId");

      if (response == null || response.statusCode != 200) {
        throw FetchTimesException(
            "Güncel vakit bilgileri getirilirken sorun oluştu.");
      }

      final List<PrayerTime> times =
          (response.data as List).map((e) => PrayerTime.fromJson(e)).toList();

      return times;
    } catch (e) {
      debugPrint("Vakitler alınırken sorun oluştu");
      rethrow;
    }
  }

  Future<EidPrayerTime> _getEidTimes(City city, String stateId) async {
    try {
      final response =
          await _dio.request("$_baseUrl/$_eidTimesUrl/${city.sehirId}");

      if (response == null || response.statusCode != 200) {
        throw FetchTimesException(
            "Bayram namazı vakitleri getirilirken sorun oluştu.");
      }

      final List<EidPrayerTime> eidTimes = (response.data as List)
          .map((e) => EidPrayerTime.fromJson(e))
          .toList();

      final singleEidTime = eidTimes.singleWhere((e) =>
          e.ilceBilgisi.ilceId == stateId ||
          e.ilceBilgisi.ilceAdi == city.sehirAdi);

      return singleEidTime;
    } catch (e) {
      debugPrint("Bayram namazı vakitleri alınırken sorun oluştu");
      rethrow;
    }
  }

  List<ReligiousDays>? _religiousDays;

  Future<List<ReligiousDays>> getReligiousDays() async {
    try {
      if (_religiousDays != null) return _religiousDays!;

      final response = await _dio.request("$ksBaseUrl/$_religiousDaysUrl");

      if (response == null || response.statusCode != 200) {
        throw FetchTimesException("Dini günler getirilirken sorun oluştu.");
      }

      final data = response.data as List;
      final List<ReligiousDays> religiousDays =
          data.map((e) => ReligiousDays.fromJson(e)).toList();

      _religiousDays = religiousDays;
      return religiousDays;
    } catch (e) {
      debugPrint("Dini günler alınırken sorun oluştu");
      rethrow;
    }
  }
}
