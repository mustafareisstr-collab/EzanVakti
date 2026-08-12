import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dini_atlas/app/app.bottomsheets.dart';
import 'package:dini_atlas/app/app.router.dart';
import 'package:dini_atlas/extensions/string_extensions.dart';
import 'package/dini_atlas/models/user_location.dart';
import 'package:dini_atlas/services/local/location_service.dart';
import 'package:dini_atlas/services/local/network_checker.dart';
import 'package:dini_atlas/services/local/prayer_times_service.dart';
import 'package:dini_atlas/services/local/user_settings_service.dart';
import 'package:dini_atlas/services/remote/fetch_times_service.dart';
import 'package/flutter_native_splash/flutter_native_splash.dart';
import 'package:stacked/stacked.dart';
import 'package:dini_atlas/app/app.locator.dart';
import 'package:stacked_services/stacked_services.dart';

class StartupViewModel extends BaseViewModel {
  final _networkChecker = locator<NetworkChecker>()..autoNavigate = false;
  final _navigationService = locator<NavigationService>();
  final _locationService = locator<LocationService>();
  final _userSettingsService = locator<UserSettingsService>();
  final _fetchTimesService = locator<FetchTimesService>();
  final _bottomSheetService = locator<BottomSheetService>();
  final _prayerTimesService = locator<PrayerTimesService>();

  void getDatas() async {
    if (_networkChecker.currentConnectivity == ConnectivityResult.none) {
      _navigationService.replaceWithNoInternetView();
    } else {
      await runBusyFuture(_fetchUserLocationAndPrayerTimes());
    }
  }

  Future<void> _fetchUserLocationAndPrayerTimes() async {
    try {
      final result = await _locationService.getUserLocation();
      await result.fold((l) async {
        await _userSettingsService.setUserLocationSettings(location: l);
        try {
          await _fetchTimesService.fetchTimes();
        } catch (_) {}
        _navigateToHomeView(true);
      }, (r) async {
        manuelFetchLocationCountry();
      });
    } catch (e) {
      setError(e.toString());
      _navigateToHomeView(false);
    }
  }

  late UserLocation _manuelSelectUserLocation;

  void manuelFetchLocationCountry({UserLocation? location}) async {
    try {
      setBusy(true);
      _manuelSelectUserLocation = location ??
          UserLocation(
            country: '',
            city: '',
            state: '',
            lat: 0.0,
            long: 0.0,
          );
      final countries = await _fetchTimesService.getCountries();
      setBusy(false);

      final country = await _bottomSheetService.showCustomSheet(
          variant: BottomSheetType.location,
          barrierDismissible: false,
          title: "Ülke Seçiniz",
          data: countries.map((e) => e.ulkeAdiEn.capitalize()).toList());
      if (country == null) return;
      final selection = countries.firstWhere(
          (e) => e.ulkeAdiEn == (country.data as String).toLowerCase());
      _manuelSelectUserLocation.country = selection.ulkeAdiEn;

      _manuelFetchLocationCity(selection.ulkeId);
    } catch (e) {
      setBusy(false);
      _navigateToHomeView(false);
    }
  }

  void _manuelFetchLocationCity(String countryId) async {
    try {
      final cities = await _fetchTimesService.getCities(countryId);
      final city = await _bottomSheetService.showCustomSheet(
        variant: BottomSheetType.location,
        barrierDismissible: false,
        title: "Şehir Seçiniz",
        data: cities.map((e) => e.sehirAdiEn.capitalize()).toList(),
      );
      if (city == null) return;
      final selection = cities
          .firstWhere((e) => e.sehirAdiEn == (city.data as String).toLowerCase());
      _manuelSelectUserLocation.city = selection.sehirAdiEn;

      _manuelFetchLocationState(selection.sehirId);
    } catch (e) {
      _navigateToHomeView(false);
    }
  }

  void _manuelFetchLocationState(String sehirId) async {
    try {
      final states = await _fetchTimesService.getStates(sehirId);
      final state = await _bottomSheetService.showCustomSheet(
        variant: BottomSheetType.location,
        barrierDismissible: false,
        title: "İlçe Seçiniz",
        data: states.map((e) => e.ilceAdiEn.capitalize()).toList(),
      );
      if (state == null) return;
      final selection = states
          .firstWhere((e) => e.ilceAdiEn == (state.data as String).toLowerCase());
      _manuelSelectUserLocation.state = selection.ilceAdiEn;

      setBusy(true);
      await _userSettingsService.setUserLocationSettings(
          location: _manuelSelectUserLocation);
      try {
        await _fetchTimesService.fetchTimes();
      } catch (_) {}
      setBusy(false);
      _navigateToHomeView(false);
    } catch (e) {
      setBusy(false);
      _navigateToHomeView(false);
    }
  }

  void _navigateToHomeView(bool autoLocation) {
    _navigationService.replaceWithHomeView();
  }

  void checkLocation({bool delayed = false}) async {
    try {
      final hasPrayerTimes = await _prayerTimesService.hasPrayerTimes();
      if (hasPrayerTimes) {
        if (delayed) await Future.delayed(const Duration(seconds: 1));
        _navigationService.replaceWithHomeView();
      } else {
        FlutterNativeSplash.remove();
      }
    } catch (_) {
      FlutterNativeSplash.remove();
    }
  }

  @override
  void dispose() {
    _networkChecker.dispose();
    super.dispose();
  }
}
