// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:io';

/// The tom_forge sample set's `files/` (`TOM_PDF_SAMPLES` overrides it).
final samplesDir =
    Platform.environment['TOM_PDF_SAMPLES'] ??
    '${Directory.current.path}/../../../_ai/quests/tom_forge/ideas/'
        'office_and_pdf_integration_prototype/samples/files';

/// The encrypted sample's user password (samples README).
const kEncryptedPassword = 'ELXRTQWS';

/// A sample's path.
String samplePath(String name) => '$samplesDir/$name';

/// Why the samples cannot be used, or `null`.
String? get samplesSkipReason => File(samplePath('pdf-text.pdf')).existsSync()
    ? null
    : 'the sample set is not at $samplesDir';
