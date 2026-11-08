#!/usr/bin/env python3
"""Build a display ICC from Piano's factory static HDR calibration.

The input is a generic QDCM file from the read-only Android system image.
No template, device-specific calibration, or dynamic HDR tone-map is used.
LittleCMS owns the ICC format, curve interpolation, and inverse pipeline.
"""

import argparse
from bisect import bisect_right
import ctypes as C
from ctypes.util import find_library
import hashlib
import json
import math
import os
from pathlib import Path
import re
import struct
from datetime import datetime, timezone
from xml.etree import ElementTree as ET


class XYZ(C.Structure):
    _fields_ = [('X', C.c_double), ('Y', C.c_double), ('Z', C.c_double)]


class xyY(C.Structure):
    _fields_ = [('x', C.c_double), ('y', C.c_double), ('Y', C.c_double)]


class Primaries(C.Structure):
    _fields_ = [('Red', xyY), ('Green', xyY), ('Blue', xyY)]


def signature(name):
    return int.from_bytes(name.encode('ascii'), 'big')


def decode(value):
    raw = bytes.fromhex(value)
    start = len(raw) % 2
    ordered = bytearray(raw[:start])
    for index in range(start, len(raw), 2):
        ordered.extend(raw[index : index + 2][::-1])
    return json.loads(ordered)


def numbers(value):
    return [int(part) for part in value.split(',') if part]


def clamp(value):
    return max(0.0, min(1.0, value))


def interpolate(points, values, value):
    if value <= points[0]:
        return values[0]
    if value >= points[-1]:
        return values[-1]
    right = bisect_right(points, value)
    left = right - 1
    fraction = (value - points[left]) / (points[right] - points[left])
    return values[left] * (1 - fraction) + values[right] * fraction


def inverse_curve(points, values, target):
    # Quantized factory curves have plateaus. Keep black at zero and use
    # the upper endpoint only for nonzero flat segments.
    if target <= values[0]:
        return points[0]
    if target >= values[-1]:
        return points[-1]
    right = bisect_right(values, target)
    left = right - 1
    fraction = (target - values[left]) / (values[right] - values[left])
    return points[left] * (1 - fraction) + points[right] * fraction


class LCMS:
    def __init__(self):
        self.library = C.CDLL(find_library('lcms2'))
        pointer = C.c_void_p
        unsigned = C.c_uint32
        float_pointer = C.POINTER(C.c_float)
        self.sampler_type = C.CFUNCTYPE(C.c_int, float_pointer, float_pointer, pointer)
        uint16_pointer = C.POINTER(C.c_uint16)
        self.sampler16_type = C.CFUNCTYPE(
            C.c_int, uint16_pointer, uint16_pointer, pointer
        )
        self.error_handler_type = C.CFUNCTYPE(None, pointer, unsigned, C.c_char_p)
        self.error_handler = self.error_handler_type(
            lambda _, code, message: print('LittleCMS', code, message.decode())
        )
        self.library.cmsSetLogErrorHandler.argtypes = [self.error_handler_type]
        self.library.cmsSetLogErrorHandler(self.error_handler)
        functions = {
            'cmsBuildTabulatedToneCurveFloat': (
                pointer,
                [pointer, unsigned, float_pointer],
            ),
            'cmsBuildGamma': (pointer, [pointer, C.c_double]),
            'cmsFreeToneCurve': (None, [pointer]),
            'cmsCreateRGBProfileTHR': (
                pointer,
                [pointer, C.POINTER(xyY), C.POINTER(Primaries), C.POINTER(pointer)],
            ),
            'cmsReadTag': (pointer, [pointer, unsigned]),
            'cmsWriteTag': (C.c_int, [pointer, unsigned, pointer]),
            'cmsLinkTag': (C.c_int, [pointer, unsigned, unsigned]),
            'cmsPipelineAlloc': (pointer, [pointer, unsigned, unsigned]),
            'cmsPipelineFree': (None, [pointer]),
            'cmsPipelineGetPtrToFirstStage': (pointer, [pointer]),
            'cmsPipelineInsertStage': (C.c_int, [pointer, C.c_int, pointer]),
            'cmsPipelineEvalFloat': (None, [float_pointer, float_pointer, pointer]),
            'cmsPipelineEvalReverseFloat': (
                C.c_int,
                [float_pointer, float_pointer, float_pointer, pointer],
            ),
            'cmsStageAllocToneCurves': (
                pointer,
                [pointer, unsigned, C.POINTER(pointer)],
            ),
            'cmsStageAllocMatrix': (
                pointer,
                [
                    pointer,
                    unsigned,
                    unsigned,
                    C.POINTER(C.c_double),
                    C.POINTER(C.c_double),
                ],
            ),
            'cmsStageAllocCLutFloat': (
                pointer,
                [pointer, unsigned, unsigned, unsigned, float_pointer],
            ),
            'cmsStageAllocCLut16bit': (
                pointer,
                [pointer, unsigned, unsigned, unsigned, uint16_pointer],
            ),
            'cmsStageSampleCLutFloat': (
                C.c_int,
                [pointer, self.sampler_type, pointer, unsigned],
            ),
            'cmsStageSampleCLut16bit': (
                C.c_int,
                [pointer, self.sampler16_type, pointer, unsigned],
            ),
            'cmsStageNext': (pointer, [pointer]),
            'cmsStageDup': (pointer, [pointer]),
            'cmsCreateProfilePlaceholder': (pointer, [pointer]),
            'cmsSetDeviceClass': (None, [pointer, unsigned]),
            'cmsSetColorSpace': (None, [pointer, unsigned]),
            'cmsSetPCS': (None, [pointer, unsigned]),
            'cmsSetProfileVersion': (None, [pointer, C.c_double]),
            'cmsSetHeaderRenderingIntent': (None, [pointer, unsigned]),
            'cmsMLUalloc': (pointer, [pointer, unsigned]),
            'cmsMLUsetASCII': (C.c_int, [pointer, C.c_char_p, C.c_char_p, C.c_char_p]),
            'cmsMLUfree': (None, [pointer]),
            'cmsDictAlloc': (pointer, [pointer]),
            'cmsDictAddEntry': (
                C.c_int,
                [pointer, C.c_wchar_p, C.c_wchar_p, pointer, pointer],
            ),
            'cmsDictFree': (None, [pointer]),
            'cmsSaveProfileToFile': (C.c_int, [pointer, C.c_char_p]),
            'cmsSaveProfileToMem': (C.c_int, [pointer, pointer, C.POINTER(unsigned)]),
            'cmsOpenProfileFromFile': (pointer, [C.c_char_p, C.c_char_p]),
            'cmsCloseProfile': (C.c_int, [pointer]),
            'cmsMD5computeID': (C.c_int, [pointer]),
        }
        for name, (result, arguments) in functions.items():
            function = getattr(self.library, name)
            function.restype = result
            function.argtypes = arguments
            setattr(self, name.removeprefix('cms'), function)

    def curve(self, points, values):
        # Use the source grids, including the factory low-light toe entries.
        # Standard ICC curv tags are limited to 32767 samples by LittleCMS.
        count = 32767
        table = (C.c_float * count)(
            *(
                interpolate(points, values, index / (count - 1))
                for index in range(count)
            )
        )
        curve = self.BuildTabulatedToneCurveFloat(None, count, table)
        if not curve:
            raise RuntimeError('LittleCMS could not allocate a tone curve')
        return curve

    def append_curves(self, pipeline, curves):
        pointers = (C.c_void_p * 3)(*curves)
        stage = self.StageAllocToneCurves(None, 3, pointers)
        if not stage or not self.PipelineInsertStage(pipeline, 1, stage):
            raise RuntimeError('LittleCMS could not append tone curves')
        for curve in set(curves):
            self.FreeToneCurve(curve)

    def evaluate(self, pipeline, values):
        source = (C.c_float * 3)(*values)
        target = (C.c_float * 3)()
        self.PipelineEvalFloat(source, target, pipeline)
        return list(target)


def read_calibration(common, mode):
    igc_config = decode(mode['PostBlendIGC'])
    gamut_config = decode(mode['PostBlendGamut'])
    gc_config = decode(mode['PostBlendGC'])
    if not all(config['enable'] for config in (igc_config, gamut_config, gc_config)):
        raise ValueError('the factory static calibration must enable IGC, gamut and GC')

    igc = numbers(common['PostBlendIGC']['Predefined'][igc_config['Predefined']])
    if len(igc) != 385:
        raise ValueError('the factory IGC must use the 257+128 high-precision grid')
    dark_limit = 127 / 1024
    igc_pairs = [(index / 1024, igc[257 + index] / 65535) for index in range(128)]
    igc_pairs.extend(
        (index / 256, igc[index] / 65535)
        for index in range(257)
        if index / 256 > dark_limit
    )
    gamut = numbers(common['PostBlendGamut']['Custom'][str(gamut_config['Custom'])])
    if len(gamut) != 17**3 * 3:
        raise ValueError('the factory gamut must contain 17 cubed RGB triples')
    gc = common['PostBlendGC']['Custom'][str(gc_config['Custom'])]
    gc_pairs = []
    for channel in ('lutR', 'lutG', 'lutB'):
        values = numbers(gc[channel])
        if len(values) != 1280:
            raise ValueError('the factory GC must use the 1024+256 high-precision grid')
        # Keep the high-precision dark table instead of a nominal gamma curve.
        # The factory 2p2 table uses 16-bit input coordinates for these 256
        # dark entries; the main table uses 10-bit input coordinates.
        dark_limit = 255 / 65535
        pairs = [(index / 65535, values[1024 + index] / 1023) for index in range(256)]
        pairs.extend(
            (index / 1023, values[index] / 1023)
            for index in range(1024)
            if index / 1023 > dark_limit
        )
        gc_pairs.append(pairs)
    return igc_pairs, gamut, gc_pairs


def matrix_inverse(matrix):
    a, b, c, d, e, f, g, h, i = matrix
    determinant = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    return [
        value / determinant
        for value in (
            e * i - f * h,
            c * h - b * i,
            b * f - c * e,
            f * g - d * i,
            a * i - c * g,
            c * d - a * f,
            d * h - e * g,
            b * g - a * h,
            a * e - b * d,
        )
    ]


def reference_matrix(cms):
    # These are the reference P3-D65 coordinates, not invented panel primaries.
    # The factory correction T converts this reference signal to device codes.
    white = xyY(0.3127, 0.3290, 1)
    primaries = Primaries(xyY(0.68, 0.32, 1), xyY(0.265, 0.69, 1), xyY(0.15, 0.06, 1))
    gamma = cms.BuildGamma(None, 2.2)
    profile = cms.CreateRGBProfileTHR(
        None, C.byref(white), C.byref(primaries), (C.c_void_p * 3)(gamma, gamma, gamma)
    )
    cms.FreeToneCurve(gamma)
    columns = [
        C.cast(cms.ReadTag(profile, signature(tag)), C.POINTER(XYZ)).contents
        for tag in ('rXYZ', 'gXYZ', 'bXYZ')
    ]
    matrix = [
        getattr(column, component)
        for component in ('X', 'Y', 'Z')
        for column in columns
    ]
    cms.CloseProfile(profile)
    return matrix


def sampled_pipeline(cms, callback, grid=33, floating=False):
    pipeline = cms.PipelineAlloc(None, 3, 3)
    cms.append_curves(pipeline, [cms.curve([0, 1], [0, 1])] * 3)
    stage = (cms.StageAllocCLutFloat if floating else cms.StageAllocCLut16bit)(
        None, grid, 3, 3, None
    )

    def sample16(source, target, cargo):
        source_float = [value / 65535 for value in source[:3]]
        target_float = [0.0, 0.0, 0.0]
        result = callback(source_float, target_float, cargo)
        for channel in range(3):
            target[channel] = math.floor(clamp(target_float[channel]) * 65535 + 0.5)
        return result

    sampler = cms.sampler_type(callback) if floating else cms.sampler16_type(sample16)
    sample = cms.StageSampleCLutFloat if floating else cms.StageSampleCLut16bit
    if not sample(stage, sampler, None, 0):
        raise RuntimeError('LittleCMS could not sample an ICC CLUT')
    if not cms.PipelineInsertStage(pipeline, 1, stage):
        raise RuntimeError('LittleCMS could not append an ICC CLUT')
    cms.append_curves(pipeline, [cms.curve([0, 1], [0, 1])] * 3)
    return pipeline


def append_matrix(cms, pipeline, matrix):
    stage = cms.StageAllocMatrix(None, 3, 3, (C.c_double * 9)(*matrix), None)
    if not stage or not cms.PipelineInsertStage(pipeline, 1, stage):
        raise RuntimeError('LittleCMS could not append the XYZ matrix')


def append_gamut(cms, pipeline, gamut, floating=False):
    # QDCM varies R fastest; LittleCMS varies its last input (B) fastest.
    table = []
    for red in range(17):
        for green in range(17):
            for blue in range(17):
                offset = ((blue * 17 + green) * 17 + red) * 3
                table.extend(
                    value / 4095 if floating else math.floor(value / 4095 * 65535 + 0.5)
                    for value in gamut[offset : offset + 3]
                )
    array = (C.c_float if floating else C.c_uint16) * len(table)
    stage = (cms.StageAllocCLutFloat if floating else cms.StageAllocCLut16bit)(
        None, 17, 3, 3, array(*table)
    )
    if not stage or not cms.PipelineInsertStage(pipeline, 1, stage):
        raise RuntimeError('LittleCMS could not append the calibration gamut')


def make_pipelines(cms, igc_pairs, gamut, gc_pairs, matrix, floating=False):
    """Preserve the source CLUT instead of coarse-sampling it in XYZ space."""
    pcs_scale = 1 if floating else 65535 / 32768
    inverse_matrix = matrix_inverse(matrix)
    igc_x, igc_y = zip(*igc_pairs)
    pre_values = [
        interpolate(igc_x, igc_y, (index / 65535) ** (1 / 2.2))
        for index in range(65536)
    ]
    unit_grid = [index / 65535 for index in range(65536)]

    # ICC mBA: B curves -> XYZ matrix -> M curves -> CLUT -> A curves.
    # The reference gamma decode and the real IGC are composed into M.
    b2a = cms.PipelineAlloc(None, 3, 3)
    cms.append_curves(b2a, [cms.curve([0, 1], [0, 1])] * 3)
    append_matrix(cms, b2a, [value * pcs_scale for value in inverse_matrix])
    if floating:
        # MPE permits separate shapers, preserving the measured zero/toe
        # of the real IGC instead of resampling a composed near-black curve.
        cms.append_curves(
            b2a, [cms.curve(unit_grid, [value ** (1 / 2.2) for value in unit_grid])] * 3
        )
        cms.append_curves(b2a, [cms.curve(igc_x, igc_y)] * 3)
    else:
        cms.append_curves(b2a, [cms.curve(unit_grid, pre_values)] * 3)
    append_gamut(cms, b2a, gamut, floating)
    cms.append_curves(b2a, [cms.curve(*zip(*pairs)) for pairs in gc_pairs])

    # Invert only the cross-channel gamut stage. Retaining curves and the
    # matrix outside this CLUT avoids large low-light interpolation errors.
    gamut_pipeline = cms.PipelineAlloc(None, 3, 3)
    append_gamut(cms, gamut_pipeline, gamut, floating)
    inverse_failures = 0

    def inverse_gamut(source, target, _):
        nonlocal inverse_failures
        result = (C.c_float * 3)()
        values = (C.c_float * 3)(*source[:3])
        if not cms.PipelineEvalReverseFloat(values, result, values, gamut_pipeline):
            inverse_failures += 1
        for channel in range(3):
            target[channel] = clamp(result[channel])
        return 1

    # ICC mAB: A curves -> inverse CLUT -> M curves -> matrix -> B curves.
    a2b = cms.PipelineAlloc(None, 3, 3)
    reversed_curves = []
    for pairs in gc_pairs:
        x, y = zip(*pairs)
        values = [inverse_curve(x, y, index / 65535) for index in range(65536)]
        reversed_curves.append(cms.curve(unit_grid, values))
    cms.append_curves(a2b, reversed_curves)

    inverse_pipeline = sampled_pipeline(cms, inverse_gamut, grid=65, floating=floating)
    # Unlink the sampled CLUT from its temporary identity curves.
    first = cms.PipelineGetPtrToFirstStage(inverse_pipeline)
    inverse_clut = cms.StageDup(cms.StageNext(first))
    if not cms.PipelineInsertStage(a2b, 1, inverse_clut):
        raise RuntimeError('LittleCMS could not append inverse gamut')
    cms.PipelineFree(inverse_pipeline)
    cms.PipelineFree(gamut_pipeline)

    if floating:
        inverse_igc = [inverse_curve(igc_x, igc_y, value) for value in unit_grid]
        cms.append_curves(a2b, [cms.curve(unit_grid, inverse_igc)] * 3)
        cms.append_curves(
            a2b, [cms.curve(unit_grid, [value**2.2 for value in unit_grid])] * 3
        )
    else:
        inverse_pre = [
            inverse_curve(unit_grid, pre_values, value) for value in unit_grid
        ]
        cms.append_curves(a2b, [cms.curve(unit_grid, inverse_pre)] * 3)
    append_matrix(cms, a2b, [value / pcs_scale for value in matrix])
    cms.append_curves(a2b, [cms.curve([0, 1], [0, 1])] * 3)
    return a2b, b2a, inverse_failures


def backlight_curve(header):
    """Invert the GPL KTZ8866 Android-level remap into Linux raw-code units.

    Android's display-device configuration maps normalized GUI levels
    .001709819/.49975574/1 to 2/600/800 nit. The kernel first remaps the
    0..4095 Android level through a normal/HBM index and this chip table;
    Linux exposes the resulting 11-bit chip value directly.
    """
    source = header.read_text()
    match = re.search(r'mi_bl_level_remap\s*\[[^]]+\]\s*=\s*\{([^}]+)\}', source, re.S)
    values = [int(value) for value in re.findall(r'\d+', match.group(1))]
    if len(values) != 2048 or values[0] != 0 or values[-1] != 2047:
        raise ValueError('the public chip remap must cover 2048 raw brightness codes')

    levels = [0, 0.001709819, 0.49975574, 1]
    luminance = [0, 2, 600, 800]
    groups = {}
    for android in range(4096):
        if 0 < android / 4095 < levels[1]:
            continue  # Android clamps nonzero requests to its minimum level.
        index = (
            android * 1535 // 2047
            if android <= 2047
            else (android - 2048) * 512 // 2047 + 1535
        )
        raw = values[index]
        groups.setdefault(raw, []).append(
            interpolate(levels, luminance, android / 4095)
        )
    # Several Android levels can request the same raw code. Their midpoint
    # defines this model; the compression error below excludes that ambiguity
    # and any difference between the factory model and measured luminance.
    points = [
        (raw / 2047, (min(nits) + max(nits)) / 1600)
        for raw, nits in sorted(groups.items())
    ]
    points[0] = (0, 0)
    points[-1] = (1, 1)

    def simplify(section):
        if len(section) <= 2:
            return section
        left, right = section[0], section[-1]
        errors = [
            abs(y - interpolate([left[0], right[0]], [left[1], right[1]], x))
            for x, y in section[1:-1]
        ]
        index = max(range(len(errors)), key=errors.__getitem__) + 1
        if errors[index - 1] * 800 <= 0.05:
            return [left, right]
        return simplify(section[: index + 1])[:-1] + simplify(section[index:])

    compressed = simplify(points)
    x, y = zip(*compressed)
    error = max(
        abs(interpolate(x, y, point_x) - point_y) * 800 for point_x, point_y in points
    )
    if error > 1:
        raise ValueError(f'backlight curve compression exceeds 1 nit: {error}')
    return ';'.join(f'{x:.9g}:{y:.9g}' for x, y in compressed), error


def normalize_profile(cms, output):
    """Fix the ICC creation timestamp, then let LittleCMS compute its ID."""
    creation = datetime.fromtimestamp(
        int(os.environ.get('SOURCE_DATE_EPOCH', '1')), timezone.utc
    )
    profile_bytes = bytearray(output.read_bytes())
    if profile_bytes[36:40] != b'acsp':
        raise ValueError('LittleCMS did not produce a standard ICC profile')
    # The ICC header has a fixed six-u16 dateTimeNumber at byte24.
    profile_bytes[24:36] = struct.pack(
        '>6H',
        creation.year,
        creation.month,
        creation.day,
        creation.hour,
        creation.minute,
        creation.second,
    )
    profile_bytes[84:100] = bytes(16)
    output.write_bytes(profile_bytes)
    profile = cms.OpenProfileFromFile(str(output).encode(), b'r')
    if not profile or not cms.MD5computeID(profile):
        raise RuntimeError('LittleCMS could not identify the reproducible profile')
    length = C.c_uint32()
    if not cms.SaveProfileToMem(profile, None, C.byref(length)):
        raise RuntimeError('LittleCMS could not save the reproducible profile')
    memory = (C.c_uint8 * length.value)()
    if not cms.SaveProfileToMem(profile, memory, C.byref(length)):
        raise RuntimeError('LittleCMS could not serialize the reproducible profile')
    cms.CloseProfile(profile)
    output.write_bytes(bytes(memory[: length.value]))


def make_profile(source, output, compatible, backlight_map):
    cms = LCMS()
    data = json.loads(source.read_text())
    panel_name = next(key for key in data if key.startswith('xiaomi'))
    panel_vendors = {
        'xiaomi_p81_42_02_0a_vid_mode_dualdsi_dsc_panel': 'boe',
        'xiaomi_p81_35_02_0b_vid_mode_dualdsi_dsc_panel': 'csot',
    }
    if compatible != f'xiaomi,piano-{panel_vendors[panel_name]}-nt36532':
        raise ValueError('the requested OF compatible does not match the QDCM panel')
    mode = data[panel_name]['native_hdr']
    common = {
        name: decode(data['Common'][name])
        for name in ('PostBlendIGC', 'PostBlendGamut', 'PostBlendGC')
    }
    xml = ET.fromstring(decode(mode['PostBlendHdrBlob'])['blob'].replace('\\"', '"'))
    peak = float(xml.findtext('panel_max_luminance'))
    black = float(xml.findtext('panel_min_luminance'))
    if (
        xml.findtext('output_gamma_space/val') != '2.2'
        or xml.findtext('panel_color_mode') != 'DCIP3'
    ):
        raise ValueError('the reference signal must be factory P3 / gamma2.2')

    igc_pairs, gamut, gc_pairs = read_calibration(common, mode)
    matrix = reference_matrix(cms)
    a2b_pipeline, b2a_pipeline, inverse_failures = make_pipelines(
        cms, igc_pairs, gamut, gc_pairs, matrix
    )
    profile = cms.CreateProfilePlaceholder(None)
    cms.SetProfileVersion(profile, 4.3)
    cms.SetDeviceClass(profile, signature('mntr'))
    cms.SetColorSpace(profile, signature('RGB '))
    cms.SetPCS(profile, signature('XYZ '))
    cms.SetHeaderRenderingIntent(profile, 1)

    white = XYZ(0.9642, 1, 0.8249)
    lumi = XYZ(0, peak, 0)
    blackpoint = XYZ(white.X * black / peak, black / peak, white.Z * black / peak)
    for tag, value in [('wtpt', white), ('lumi', lumi), ('bkpt', blackpoint)]:
        if not cms.WriteTag(profile, signature(tag), C.byref(value)):
            raise RuntimeError(f'LittleCMS could not write {tag}')
    for tag, pipeline in [('A2B0', a2b_pipeline), ('B2A0', b2a_pipeline)]:
        if not cms.WriteTag(profile, signature(tag), pipeline):
            raise RuntimeError(f'LittleCMS could not write {tag}')
    for tag, destination in [
        ('A2B1', 'A2B0'),
        ('A2B2', 'A2B0'),
        ('B2A1', 'B2A0'),
        ('B2A2', 'B2A0'),
    ]:
        cms.LinkTag(profile, signature(tag), signature(destination))

    # ICC v4 floating-point MPE tags avoid signed-15.16 matrix rounding in
    # the near-black gamut conversion. Keep mAB/mBA for older CMM readers.
    d2b, b2d, _ = make_pipelines(cms, igc_pairs, gamut, gc_pairs, matrix, floating=True)
    for tag, pipeline in [('D2B0', d2b), ('B2D0', b2d)]:
        if not cms.WriteTag(profile, signature(tag), pipeline):
            raise RuntimeError(f'LittleCMS could not write {tag}')
    for direction in ('D2B', 'B2D'):
        for intent in (1, 2, 3):
            cms.LinkTag(
                profile, signature(f'{direction}{intent}'), signature(f'{direction}0')
            )
    cms.PipelineFree(d2b)
    cms.PipelineFree(b2d)

    description = cms.MLUalloc(None, 1)
    cms.MLUsetASCII(description, b'en', b'US', b'Xiaomi Pad 8 Pro')
    cms.WriteTag(profile, signature('desc'), description)
    cms.MLUsetASCII(
        description,
        b'en',
        b'US',
        b'Calibration derived from the device factory QDCM configuration.',
    )
    cms.WriteTag(profile, signature('cprt'), description)
    cms.MLUfree(description)
    metadata = cms.DictAlloc(None)
    backlight, backlight_error = backlight_curve(backlight_map)
    for name, value in {
        'MUTTER_native_hdr': '1',
        'MUTTER_native_hdr_reference': 'p3-gamma22',
        'MAPPING_device_of_compatible': compatible,
        'MUTTER_backlight_luminance': backlight,
        'DATA_source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
        'DATA_source_panel': panel_name,
    }.items():
        cms.DictAddEntry(metadata, name, value, None, None)
    cms.WriteTag(profile, signature('meta'), metadata)
    cms.DictFree(metadata)
    if not cms.SaveProfileToFile(profile, str(output).encode()):
        raise RuntimeError('LittleCMS could not serialize the ICC profile')
    cms.CloseProfile(profile)
    normalize_profile(cms, output)
    for pipeline in (a2b_pipeline, b2a_pipeline):
        cms.PipelineFree(pipeline)
    print(
        json.dumps(
            {
                'profile': str(output),
                'inverse_unreachable_grid_samples': inverse_failures,
                'luminance_nit': peak,
                'black_nit': black,
                'backlight_compression_error_nit': backlight_error,
            },
            indent=2,
        )
    )


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--compatible', required=True)
    parser.add_argument('--backlight-map', type=Path, required=True)
    arguments = parser.parse_args()
    make_profile(
        arguments.source,
        arguments.output,
        arguments.compatible,
        arguments.backlight_map,
    )
