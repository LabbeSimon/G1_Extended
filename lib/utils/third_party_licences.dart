import 'package:flutter/foundation.dart';

/// Registers the licences of code that is compiled into the app but is not a
/// Dart package.
///
/// Flutter collects the licences of everything it pulls from pub, which covers
/// most of what ships here. It cannot see the C sources vendored under
/// `android/app/src/main/cpp`, nor the native library Vosk brings with it, yet
/// those are compiled into the APK and both their licences require the notice
/// to travel with the binary. Registering them here is what puts them in front
/// of the user, under Settings > About > Licence.
void registerThirdPartyLicences() {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['liblc3'],
      'The LC3 codec that decodes audio from the glasses microphone.\n\n'
      'Copyright 2022 Google LLC\n\n'
      'Licensed under the Apache License, Version 2.0 (the "License"); you '
      'may not use this file except in compliance with the License. You may '
      'obtain a copy of the License at:\n\n'
      '    http://www.apache.org/licenses/LICENSE-2.0\n\n'
      'Unless required by applicable law or agreed to in writing, software '
      'distributed under the License is distributed on an "AS IS" BASIS, '
      'WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or '
      'implied. See the License for the specific language governing '
      'permissions and limitations under the License.',
    );

    yield const LicenseEntryWithLineBreaks(
      ['rnnoise'],
      'Noise suppression applied to captured audio.\n\n'
      'Copyright (c) 2008-2011 Octasic Inc.\n'
      'Copyright (c) 2012-2017 Jean-Marc Valin\n\n'
      'Redistribution and use in source and binary forms, with or without '
      'modification, are permitted provided that the following conditions are '
      'met:\n\n'
      '- Redistributions of source code must retain the above copyright '
      'notice, this list of conditions and the following disclaimer.\n\n'
      '- Redistributions in binary form must reproduce the above copyright '
      'notice, this list of conditions and the following disclaimer in the '
      'documentation and/or other materials provided with the '
      'distribution.\n\n'
      'THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS '
      '"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT '
      'LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR '
      'A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT '
      'OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, '
      'SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES HOWEVER CAUSED AND ON ANY '
      'THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT '
      'ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF '
      'THE POSSIBILITY OF SUCH DAMAGE.',
    );

    yield const LicenseEntryWithLineBreaks(
      ['Vosk'],
      'Offline speech recognition, and the acoustic model downloaded on '
      'first use.\n\n'
      'Copyright Alpha Cephei Inc.\n\n'
      'Licensed under the Apache License, Version 2.0. You may obtain a copy '
      'of the License at:\n\n'
      '    http://www.apache.org/licenses/LICENSE-2.0',
    );

    yield const LicenseEntryWithLineBreaks(
      ['G1 Extended'],
      'BSD 2-Clause License\n\n'
      'Copyright (c) 2024, even-realities\n\n'
      'Redistribution and use in source and binary forms, with or without '
      'modification, are permitted provided that the following conditions are '
      'met:\n\n'
      '1. Redistributions of source code must retain the above copyright '
      'notice, this list of conditions and the following disclaimer.\n\n'
      '2. Redistributions in binary form must reproduce the above copyright '
      'notice, this list of conditions and the following disclaimer in the '
      'documentation and/or other materials provided with the '
      'distribution.\n\n'
      'THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS '
      '"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT '
      'LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR '
      'A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT '
      'HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, '
      'SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES.',
    );
  });
}
