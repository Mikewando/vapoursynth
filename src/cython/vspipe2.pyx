#
# Copyright (c) 2013-2026 Fredrik Mellbin
#
# This file is part of VapourSynth.
#
# VapourSynth is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# VapourSynth is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with VapourSynth; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
#

# distutils: language = c++
# cython: language_level = 3

from cpython cimport Py_INCREF, Py_DECREF

from vapoursynth cimport (
    VSAPI, VSNode, VSCore, VSFrame, VSMap,
    VSVideoFormat, VSAudioFormat, VSVideoInfo, VSAudioInfo,
    VSCoreInfo, VSLogHandle, VSPlugin,
    VSFrameDoneCallback, VSLogHandler, VSLogHandlerFree,
    cfGray, cfRGB, cfYUV,
    stInteger, stFloat,
    mtVideo, mtAudio,
    mtDebug, mtInformation, mtWarning, mtCritical, mtFatal,
    dtUtf8,
    maReplace, maAppend,
    ccfEnableGraphInspection, ccfEnableFrameRefDebug,
    acFrontLeft, acFrontRight, acFrontCenter, acLowFrequency,
    acBackLeft, acBackRight, acFrontLeftOFCenter, acFrontRightOFCenter,
    acBackCenter, acSideLeft, acSideRight,
    acTopCenter, acTopFrontLeft, acTopFrontCenter, acTopFrontRight,
    acTopBackLeft, acTopBackCenter, acTopBackRight,
    acStereoLeft, acStereoRight,
    acWideLeft, acWideRight,
    acSurroundDirectLeft, acSurroundDirectRight, acLowFrequency2,
    VS_AUDIO_FRAME_SAMPLES,
    VAPOURSYNTH_API_VERSION,
)

cdef extern from "vsscript/vsscript_internal.h" nogil:
    ctypedef struct VSScript:
        void *pyenvdict
        void *errstr
        VSCore *core
        int id
        int exitCode
        int setCWD

cdef extern from "cython/vapoursynth_api.h":
    int import_vapoursynth() nogil
    int vpy4_initVSScript() nogil
    int vpy4_createScript(VSScript *se) nogil
    void vpy4_freeScript(VSScript *se) noexcept nogil
    int vpy4_evaluateFile(VSScript *se, const char *scriptFilename) nogil
    const char *vpy4_getError(VSScript *se) nogil
    int vpy4_setVariables(VSScript *se, const VSMap *vars) nogil
    VSNode *vpy4_getOutput(VSScript *se, int index) nogil
    VSNode *vpy4_getAlphaOutput(VSScript *se, int index) nogil
    int vpy4_getAltOutputMode(VSScript *se, int index) nogil
    int vpy4_getAvailableOutputNodes(VSScript *se, int size, int *dst) nogil
    VSCore *vpy4_getCore(VSScript *se) nogil
    const VSAPI *vpy4_getVSAPI(int version) nogil

# The vapoursynth_api.h header uses p_Py* function pointer indirection
# (designed for vsscript.cpp which loads Python dynamically). Since vspipe2
# is already running inside Python, we initialize these pointers to the
# actual Python C API functions before calling import_vapoursynth().
cdef extern from * nogil:
    """
    static void _vspy_init_api_pointers() {
        p_Py_DecRef = _Py_DecRef;
        p_PyObject_GetAttrString = PyObject_GetAttrString;
        p_PyDict_GetItemString = PyDict_GetItemString;
        p_PyCapsule_IsValid = PyCapsule_IsValid;
        p_PyCapsule_GetPointer = PyCapsule_GetPointer;
        p_PyImport_ImportModule = PyImport_ImportModule;
        p_Py_IsInitialized = Py_IsInitialized;
        p_Py_InitializeEx = Py_InitializeEx;
        p_PyGILState_Ensure = PyGILState_Ensure;
        p_PyEval_SaveThread = PyEval_SaveThread;
        p_Py_SetProgramName = Py_SetProgramName;
    }
    """
    void _vspy_init_api_pointers()
from libc.stdint cimport int64_t, uint64_t, uint8_t, uintptr_t
from libc.stddef cimport ptrdiff_t, size_t
from libc.stdlib cimport malloc, free
from libc.string cimport memset
from libcpp.string cimport string

cdef extern from "vspipe/printgraph.h":
    cdef cppclass NodePrintMode "NodePrintMode":
        pass
    NodePrintMode NodePrintMode_Simple "NodePrintMode::Simple"
    NodePrintMode NodePrintMode_Full "NodePrintMode::Full"
    NodePrintMode NodePrintMode_FullWithTimes "NodePrintMode::FullWithTimes"
    string printNodeGraph(NodePrintMode mode, VSNode *node,
                          double processingTime, const VSAPI *vsapi)
    string printNodeTimes(VSNode *node, double processingTime,
                          int64_t freedTime, const VSAPI *vsapi)

cdef extern from "vspipe/vsjson.h":
    string convertVSMapToJSON(const VSMap *vmap, const VSAPI *vsapi)

cdef extern from "common/wave.h":
    struct WaveFormatExtensible:
        pass
    struct WaveHeader:
        pass
    struct Wave64Header:
        pass
    bint CreateWaveHeader(WaveHeader &header, bint IsFloat, int BitsPerSample,
                          int SampleRate, uint64_t ChannelMask, int64_t NumSamples)
    bint CreateWave64Header(Wave64Header &header, bint IsFloat, int BitsPerSample,
                            int SampleRate, uint64_t ChannelMask, int64_t NumSamples)
    void PackChannels16to16le(const uint8_t *const *Src, uint8_t *Dst, size_t Length, size_t Channels) nogil
    void PackChannels32to32le(const uint8_t *const *Src, uint8_t *Dst, size_t Length, size_t Channels) nogil
    void PackChannels32to24le(const uint8_t *const *Src, uint8_t *Dst, size_t Length, size_t Channels) nogil

cdef extern from "VSHelper4.h" namespace "vsh" nogil:
    bint isConstantVideoFormat(const VSVideoInfo *vi) nogil
    void bitblt(void *dstp, ptrdiff_t dst_stride, const void *srcp,
                ptrdiff_t src_stride, size_t row_size, size_t height) nogil


# ---------------------------------------------------------------------------
# Log handler (C callback for VSAPI)
# ---------------------------------------------------------------------------

cdef const char* _msgtype_name(int msgType) noexcept nogil:
    if msgType == mtDebug: return "Debug"
    if msgType == mtInformation: return "Information"
    if msgType == mtWarning: return "Warning"
    if msgType == mtCritical: return "Critical"
    if msgType == mtFatal: return "Fatal"
    return ""

cdef void _log_handler(int msgType, const char *msg, void *userData) noexcept nogil:
    if msgType >= mtInformation:
        with gil:
            import sys
            sys.stderr.write(
                f"{_msgtype_name(msgType).decode('utf-8')}: "
                f"{msg.decode('utf-8', errors='replace')}\n")


# ---------------------------------------------------------------------------
# Output state (mirrors VSPipeOutputData in vspipe.cpp)
# ---------------------------------------------------------------------------

cdef class _FramePair:
    cdef const VSFrame *first
    cdef const VSFrame *second

    def __cinit__(self):
        self.first = NULL
        self.second = NULL


cdef class _OutputState:
    cdef const VSAPI *vsapi
    cdef VSNode *node
    cdef VSNode *alphaNode

    cdef object fileobj
    cdef object timecodes_fileobj
    cdef object json_fileobj

    cdef int totalFrames
    cdef int64_t totalSamples
    cdef int outputFrames
    cdef int requestedFrames
    cdef int completedFrames
    cdef int completedAlphaFrames

    cdef dict reorderMap

    cdef bint outputError
    cdef str errorMessage

    cdef bint printProgress
    cdef bint y4m
    cdef bint isVideo

    cdef double startTime
    cdef double lastFPSReportTime

    cdef dict currentTimecode

    cdef uint8_t *buffer
    cdef size_t bufferSize

    cdef object condition

    def __cinit__(self):
        self.reorderMap = {}
        self.currentTimecode = {}
        self.buffer = NULL
        self.bufferSize = 0
        self.outputError = False
        self.errorMessage = ''
        self.totalSamples = 0

    def __dealloc__(self):
        if self.buffer != NULL:
            free(self.buffer)
            self.buffer = NULL

    cdef void ensureBuffer(self, size_t needed) except *:
        if needed > self.bufferSize:
            if self.buffer != NULL:
                free(self.buffer)
            self.buffer = <uint8_t *>malloc(needed)
            if self.buffer == NULL:
                raise MemoryError("Failed to allocate output buffer")
            self.bufferSize = needed


# ---------------------------------------------------------------------------
# Frame writing (GIL must be held)
# ---------------------------------------------------------------------------

cdef void outputVideoFrame(const VSFrame *frame, _OutputState data) noexcept:
    cdef const VSVideoFormat *fi = data.vsapi.getVideoFrameFormat(frame)
    cdef int rgbRemap[3]
    cdef int rp, p, rowSize, height
    cdef ptrdiff_t stride
    cdef const uint8_t *readPtr

    rgbRemap[0] = 1; rgbRemap[1] = 2; rgbRemap[2] = 0

    for rp in range(fi.numPlanes):
        p = rgbRemap[rp] if fi.colorFamily == cfRGB else rp
        stride = data.vsapi.getStride(frame, p)
        readPtr = data.vsapi.getReadPtr(frame, p)
        rowSize = data.vsapi.getFrameWidth(frame, p) * fi.bytesPerSample
        height = data.vsapi.getFrameHeight(frame, p)

        if rowSize != <int>stride:
            try:
                data.ensureBuffer(<size_t>(rowSize * height))
            except MemoryError as exc:
                if not data.errorMessage:
                    data.errorMessage = str(exc)
                data.outputError = True
                data.totalFrames = data.requestedFrames
                return
            with nogil:
                bitblt(data.buffer, rowSize, readPtr, stride, rowSize, height)
            readPtr = data.buffer

        try:
            data.fileobj.write((<uint8_t *>readPtr)[:rowSize * height])
        except Exception as exc:
            if not data.errorMessage:
                data.errorMessage = (
                    f"Error: fwrite() call failed when writing frame: "
                    f"{data.outputFrames}, plane: {p}, error: {exc}")
            data.outputError = True
            data.totalFrames = data.requestedFrames
            return


cdef void outputAudioFrame(const VSFrame *frame, _OutputState data) noexcept:
    cdef const VSAudioFormat *fi = data.vsapi.getAudioFrameFormat(frame)
    cdef int numChannels = fi.numChannels
    cdef int numSamples = data.vsapi.getFrameLength(frame)
    cdef size_t bytesPerOutputSample = (fi.bitsPerSample + 7) // 8
    cdef size_t toOutput = bytesPerOutputSample * numSamples * numChannels
    cdef const uint8_t **srcPtrs = NULL
    cdef int ch

    try:
        data.ensureBuffer(toOutput)
    except MemoryError as exc:
        if not data.errorMessage:
            data.errorMessage = str(exc)
        data.outputError = True
        data.totalFrames = data.requestedFrames
        return

    srcPtrs = <const uint8_t **>malloc(numChannels * sizeof(const uint8_t *))
    if srcPtrs == NULL:
        if not data.errorMessage:
            data.errorMessage = "Error: failed to allocate channel pointer array"
        data.outputError = True
        data.totalFrames = data.requestedFrames
        return

    try:
        for ch in range(numChannels):
            srcPtrs[ch] = data.vsapi.getReadPtr(frame, ch)

        with nogil:
            if bytesPerOutputSample == 2:
                PackChannels16to16le(srcPtrs, data.buffer, numSamples, numChannels)
            elif bytesPerOutputSample == 3:
                PackChannels32to24le(srcPtrs, data.buffer, numSamples, numChannels)
            else:
                PackChannels32to32le(srcPtrs, data.buffer, numSamples, numChannels)

        try:
            data.fileobj.write(data.buffer[:toOutput])
        except Exception as exc:
            if not data.errorMessage:
                data.errorMessage = (
                    f"Error: fwrite() call failed when writing frame: "
                    f"{data.outputFrames}, error: {exc}")
            data.outputError = True
            data.totalFrames = data.requestedFrames
    finally:
        free(srcPtrs)


# ---------------------------------------------------------------------------
# Reorder + output drain (called with condition lock held)
# ---------------------------------------------------------------------------

cdef double getCurrentTimecode(dict currentTimecode) noexcept:
    cdef double total = 0.0
    for (num, den), count in currentTimecode.items():
        total += count * (<double>num / <double>den)
    return total

cdef void drainReorderMap(_OutputState data) noexcept:
    cdef _FramePair pair
    cdef const VSFrame *frame
    cdef const VSFrame *alphaFrame
    cdef const VSMap *props
    cdef int err_num, err_den
    cdef int64_t durationNum, durationDen

    while data.outputFrames in data.reorderMap:
        pair = <_FramePair>data.reorderMap[data.outputFrames]
        if data.alphaNode != NULL and pair.second == NULL and pair.first != NULL:
            break
        if pair.first == NULL:
            break

        del data.reorderMap[data.outputFrames]
        frame = pair.first
        alphaFrame = pair.second

        if not data.outputError:
            if data.y4m and data.fileobj is not None:
                try:
                    data.fileobj.write(b'FRAME\n')
                except Exception as exc:
                    if not data.errorMessage:
                        data.errorMessage = f"Error: fwrite() failed writing FRAME header: {exc}"
                    data.outputError = True
                    data.totalFrames = data.requestedFrames

            if not data.outputError and data.fileobj is not None:
                if data.isVideo:
                    outputVideoFrame(frame, data)
                else:
                    outputAudioFrame(frame, data)
                if alphaFrame != NULL and not data.outputError:
                    outputVideoFrame(alphaFrame, data)

            if not data.outputError and data.timecodes_fileobj is not None:
                tc = getCurrentTimecode(data.currentTimecode) * 1000.0
                try:
                    data.timecodes_fileobj.write(f"{tc:.6f}\n".encode())
                except Exception as exc:
                    if not data.errorMessage:
                        data.errorMessage = f"Error: failed to write timecodes at frame {data.outputFrames}: {exc}"
                    data.outputError = True
                    data.totalFrames = data.requestedFrames

                if not data.outputError:
                    props = data.vsapi.getFramePropertiesRO(frame)
                    err_num = 0; err_den = 0
                    durationNum = data.vsapi.mapGetInt(props, "_DurationNum", 0, &err_num)
                    durationDen = data.vsapi.mapGetInt(props, "_DurationDen", 0, &err_den)
                    if err_num or err_den or durationDen <= 0 or durationNum <= 0:
                        if not data.errorMessage:
                            data.errorMessage = f"Error: missing or invalid duration at frame {data.outputFrames}"
                        data.outputError = True
                        data.totalFrames = data.requestedFrames
                    else:
                        key = (int(durationNum), int(durationDen))
                        data.currentTimecode[key] = data.currentTimecode.get(key, 0) + 1

            if not data.outputError and data.json_fileobj is not None:
                props = data.vsapi.getFramePropertiesRO(frame)
                json_str = convertVSMapToJSON(props, data.vsapi).decode('utf-8')
                comma = "," if data.outputFrames < data.totalFrames - 1 else ""
                try:
                    data.json_fileobj.write(f"\t{json_str}{comma}\n".encode())
                except Exception as exc:
                    if not data.errorMessage:
                        data.errorMessage = f"Error: failed to write JSON for frame {data.outputFrames}: {exc}"
                    data.outputError = True
                    data.totalFrames = data.requestedFrames

        data.vsapi.freeFrame(frame)
        if alphaFrame != NULL:
            data.vsapi.freeFrame(alphaFrame)
        data.outputFrames += 1


# ---------------------------------------------------------------------------
# Frame-done callback
# ---------------------------------------------------------------------------

cdef void frameDoneCallback(
        void *userData, const VSFrame *f, int n,
        VSNode *rnode, const char *errorMsg) noexcept nogil:
    with gil:
        frameDoneImpl(<_OutputState>userData, f, n, rnode, errorMsg)


cdef void frameDoneImpl(
        _OutputState data, const VSFrame *f, int n,
        VSNode *rnode, const char *errorMsg) noexcept:
    cdef _FramePair pair
    cdef bint printToConsole = False
    cdef bint hasMeaningfulFPS = False
    cdef bint completed = False
    cdef double fps = 0.0

    import time as _time
    import sys as _sys

    with data.condition:
        if data.printProgress:
            currentTime = _time.monotonic()
            elapsedFromStart = currentTime - data.startTime
            elapsedSinceLast = currentTime - data.lastFPSReportTime

            printToConsole = (n == 0)
            if elapsedSinceLast > 0.5:
                printToConsole = True
                data.lastFPSReportTime = currentTime

            if elapsedFromStart > 8.0 and data.completedFrames > 0:
                hasMeaningfulFPS = True
                fps = data.completedFrames / elapsedFromStart

        if rnode == data.node:
            data.completedFrames += 1
            if data.alphaNode == NULL:
                data.completedAlphaFrames += 1
        else:
            data.completedAlphaFrames += 1

        if f != NULL:
            n_int = int(n)
            if n_int not in data.reorderMap:
                data.reorderMap[n_int] = _FramePair.__new__(_FramePair)
            pair = <_FramePair>data.reorderMap[n_int]

            if rnode == data.node:
                pair.first = f
            else:
                pair.second = f

            # Check if completed and request next
            if data.alphaNode != NULL:
                completed = pair.first != NULL and pair.second != NULL
            else:
                completed = pair.first != NULL

            if completed and data.requestedFrames < data.totalFrames:
                data.vsapi.getFrameAsync(
                    data.requestedFrames, data.node,
                    <VSFrameDoneCallback>frameDoneCallback, <void *>data)
                if data.alphaNode != NULL:
                    data.vsapi.getFrameAsync(
                        data.requestedFrames, data.alphaNode,
                        <VSFrameDoneCallback>frameDoneCallback, <void *>data)
                data.requestedFrames += 1

            drainReorderMap(data)
        else:
            data.outputError = True
            data.totalFrames = data.requestedFrames
            if not data.errorMessage:
                if errorMsg != NULL:
                    data.errorMessage = (
                        f"Error: Failed to retrieve frame {n} with error: "
                        f"{errorMsg.decode('utf-8', errors='replace')}")
                else:
                    data.errorMessage = f"Error: Failed to retrieve frame {n}"

        if printToConsole and not data.outputError:
            if data.isVideo:
                if hasMeaningfulFPS:
                    _sys.stderr.write(
                        f"Frame: {data.completedFrames}/{data.totalFrames}"
                        f" ({fps:.2f} fps)\r")
                else:
                    _sys.stderr.write(
                        f"Frame: {data.completedFrames}/{data.totalFrames}\r")
            else:
                completedSamples = data.completedFrames * VS_AUDIO_FRAME_SAMPLES
                totalSamples = data.totalFrames * VS_AUDIO_FRAME_SAMPLES
                if hasMeaningfulFPS:
                    _sys.stderr.write(
                        f"Sample: {completedSamples}/{totalSamples}"
                        f" ({fps:.2f} sps)\r")
                else:
                    _sys.stderr.write(
                        f"Sample: {completedSamples}/{totalSamples}\r")
            _sys.stderr.flush()

        if (data.totalFrames == data.completedFrames and
                data.totalFrames == data.completedAlphaFrames):
            data.condition.notify_all()


# ---------------------------------------------------------------------------
# Frame request loop
# ---------------------------------------------------------------------------

cdef int outputNode(_OutputState data, int requests, VSCore *core) except -1:
    cdef const VSAPI *vsapi = data.vsapi
    cdef int n
    cdef VSCoreInfo info

    if requests < 1:
        vsapi.getCoreInfo(core, &info)
        requests = info.numThreads

    import time
    data.startTime = time.monotonic()
    data.lastFPSReportTime = data.startTime

    cdef int initialRequestSize = min(requests, data.totalFrames)
    data.requestedFrames = initialRequestSize

    Py_INCREF(data)
    try:
        for n in range(initialRequestSize):
            vsapi.getFrameAsync(n, data.node,
                                <VSFrameDoneCallback>frameDoneCallback,
                                <void *>data)
            if data.alphaNode != NULL:
                vsapi.getFrameAsync(n, data.alphaNode,
                                    <VSFrameDoneCallback>frameDoneCallback,
                                    <void *>data)

        with data.condition:
            data.condition.wait_for(
                lambda: (data.totalFrames == data.completedFrames and
                         data.totalFrames == data.completedAlphaFrames))
    finally:
        Py_DECREF(data)

    if data.outputError:
        for pair_obj in data.reorderMap.values():
            pair = <_FramePair>pair_obj
            if pair.first != NULL:
                vsapi.freeFrame(pair.first)
            if pair.second != NULL:
                vsapi.freeFrame(pair.second)

    return 0


# ---------------------------------------------------------------------------
# Info helpers
# ---------------------------------------------------------------------------

cdef str channelMaskToName(uint64_t v):
    parts = []
    _checks = [
        (acFrontLeft, "Front Left"), (acFrontRight, "Front Right"),
        (acFrontCenter, "Center"), (acLowFrequency, "LFE"),
        (acBackLeft, "Back Left"), (acBackRight, "Back Right"),
        (acFrontLeftOFCenter, "Front Left of Center"),
        (acFrontRightOFCenter, "Front Right of Center"),
        (acBackCenter, "Back Center"),
        (acSideLeft, "Side Left"), (acSideRight, "Side Right"),
        (acTopCenter, "Top Center"),
        (acTopFrontLeft, "Top Front Left"),
        (acTopFrontCenter, "Top Front Center"),
        (acTopFrontRight, "Top Front Right"),
        (acTopBackLeft, "Top Back Left"),
        (acTopBackCenter, "Top Back Center"),
        (acTopBackRight, "Top Back Right"),
        (acStereoLeft, "Stereo Left"), (acStereoRight, "Stereo Right"),
        (acWideLeft, "Wide Left"), (acWideRight, "Wide Right"),
        (acSurroundDirectLeft, "Surround Direct Left"),
        (acSurroundDirectRight, "Surround Direct Right"),
        (acLowFrequency2, "LFE2"),
    ]
    for bit, name in _checks:
        if (<uint64_t>1 << bit) & v:
            parts.append(name)
    return ", ".join(parts)


cdef str colorFamilyToString(int cf):
    if cf == cfGray: return "Gray"
    if cf == cfRGB: return "RGB"
    if cf == cfYUV: return "YUV"
    return "Error"


cdef str floatBitsToLetter(int bits):
    if bits == 16: return "h"
    if bits == 32: return "s"
    if bits == 64: return "d"
    return "u"


# ---------------------------------------------------------------------------
# Help text
# ---------------------------------------------------------------------------

HELP_TEXT = """\
vspipe2 usage:
  vspipe2 [options] <script> <outfile>

Available options:
  -a, --arg key=value              Argument to pass to the script environment
  -s, --start N                    Set output frame/sample range start
  -e, --end N                      Set output frame/sample range end (inclusive)
  -o, --outputindex N              Select output index
  -r, --requests N                 Set number of concurrent frame requests
  -c, --container <y4m/wav/w64>    Add headers for the specified format to the output
  -t, --timecodes FILE             Write timecodes v2 file
  -j, --json FILE                  Write properties of output frames in json format to file
  -p, --progress                   Print progress to stderr
      --filter-time                Print time spent in individual filters to stderr after processing
      --filter-time-graph FILE     Write output node's filter graph in dot format with time information after processing
  -i, --info                       Print all set output node info to <outfile> and exit
  -g  --graph <simple/full>        Print output node's filter graph in dot format to <outfile> and exit
      --frame-ref-debug            Print frame allocation debug information
  -v, --version                    Show version info and exit

Special output options for <outfile>:
  -                                Write to stdout
  --                               No output

Examples:
  Show script info:
    vspipe2 --info script.vpy
  Write to stdout:
    vspipe2 [options] script.vpy -
  Request all frames but don't output them:
    vspipe2 [options] script.vpy --
  Write frames 5-100 to file:
    vspipe2 --start 5 --end 100 script.vpy output.raw
  Pass values to a script:
    vspipe2 --arg deinterlace=yes --arg "message=fluffy kittens" script.vpy output.raw
  Pipe to x264 and write timecodes file:
    vspipe2 script.vpy - -c y4m --timecodes timecodes.txt | x264 --demuxer y4m -o script.mkv -
"""


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    import sys
    import os
    import time
    import threading

    cdef const VSAPI *vsapi
    cdef VSCore *core
    cdef VSScript se
    cdef VSNode *node = NULL
    cdef VSNode *alphaNode = NULL
    cdef const VSVideoInfo *vi
    cdef const VSAudioInfo *ai
    cdef VSCoreInfo coreInfo
    cdef VSLogHandle *logHandle = NULL
    cdef char formatName[32]
    cdef int nodeType
    cdef int numOutputs
    cdef int *outputIndices = NULL
    cdef VSMap *argsMap = NULL
    cdef VSMap *trimArgs = NULL
    cdef VSMap *trimResult = NULL
    cdef VSMap *alphaTrimResult = NULL
    cdef VSPlugin *stdPlugin
    cdef WaveHeader waveHdr
    cdef Wave64Header wave64Hdr
    cdef _OutputState data
    cdef _FramePair pair
    cdef NodePrintMode graphMode
    cdef int mapErr = 0
    cdef int creationFlags = 0
    cdef const char *err = NULL

    # ---- Parse arguments ----
    args_list = sys.argv[1:]
    mode = 'output'
    container = None
    script_args = {}
    startPos = 0
    endPos = -1
    outputIndex = 0
    requests = 0
    printProgress = False
    frameRefDebug = False
    printFilterTime = False
    filterTimeGraphFile = None
    timecodesFile = None
    jsonFile = None
    graphType = None
    scriptFilename = None
    outputFilename = None

    n_args = len(args_list)
    i = 0
    while i < n_args:
        a = args_list[i]
        if a in ('-v', '--version'):
            if n_args > 1:
                sys.stderr.write(
                    "Cannot combine version information with other options\n")
                return 1
            mode = 'version'
        elif a in ('-c', '--container'):
            i += 1
            if i >= n_args:
                sys.stderr.write("No container type specified\n"); return 1
            c_val = args_list[i]
            if c_val not in ('y4m', 'wav', 'w64'):
                sys.stderr.write(f"Unknown container type specified: {c_val}\n")
                return 1
            container = c_val
        elif a in ('-p', '--progress'):
            printProgress = True
        elif a == '--frame-ref-debug':
            frameRefDebug = True
        elif a == '--filter-time':
            printFilterTime = True
        elif a == '--filter-time-graph':
            i += 1
            if i >= n_args:
                sys.stderr.write("No filter time graph file specified\n"); return 1
            filterTimeGraphFile = args_list[i]
        elif a in ('-i', '--info'):
            if mode == 'graph':
                sys.stderr.write("Cannot combine graph and info arguments\n"); return 1
            mode = 'info'
        elif a in ('-g', '--graph'):
            if mode == 'info':
                sys.stderr.write("Cannot combine graph and info arguments\n"); return 1
            i += 1
            if i >= n_args:
                sys.stderr.write("No graph type specified\n"); return 1
            g_val = args_list[i]
            if g_val not in ('simple', 'full'):
                sys.stderr.write(f"Unknown graph type specified: {g_val}\n"); return 1
            mode = 'graph'
            graphType = g_val
        elif a in ('-h', '--help'):
            if n_args > 1:
                sys.stderr.write("Cannot combine help with other options\n"); return 1
            mode = 'help'
        elif a in ('-s', '--start'):
            i += 1
            if i >= n_args:
                sys.stderr.write("No start frame specified\n"); return 1
            try:
                startPos = int(args_list[i])
            except ValueError:
                sys.stderr.write(
                    f"Couldn't convert {args_list[i]} to an integer (start)\n")
                return 1
            if startPos < 0:
                sys.stderr.write("Negative start position specified\n"); return 1
        elif a in ('-e', '--end'):
            i += 1
            if i >= n_args:
                sys.stderr.write("No end frame specified\n"); return 1
            try:
                endPos = int(args_list[i])
            except ValueError:
                sys.stderr.write(
                    f"Couldn't convert {args_list[i]} to an integer (end)\n")
                return 1
            if endPos < 0:
                sys.stderr.write("Negative end position specified\n"); return 1
        elif a in ('-o', '--outputindex'):
            i += 1
            if i >= n_args:
                sys.stderr.write("No output index specified\n"); return 1
            try:
                outputIndex = int(args_list[i])
            except ValueError:
                sys.stderr.write(
                    f"Couldn't convert {args_list[i]} to an integer (index)\n")
                return 1
        elif a in ('-r', '--requests'):
            i += 1
            if i >= n_args:
                sys.stderr.write("Number of requests not specified\n"); return 1
            try:
                requests = int(args_list[i])
            except ValueError:
                sys.stderr.write(
                    f"Couldn't convert {args_list[i]} to an integer (requests)\n")
                return 1
        elif a in ('-a', '--arg'):
            i += 1
            if i >= n_args:
                sys.stderr.write("No argument specified\n"); return 1
            arg_str = args_list[i]
            eq = arg_str.find('=')
            if eq < 0:
                sys.stderr.write(f"No value specified for argument: {arg_str}\n")
                return 1
            script_args[arg_str[:eq]] = arg_str[eq + 1:]
        elif a in ('-t', '--timecodes'):
            i += 1
            if i >= n_args:
                sys.stderr.write("No timecodes file specified\n"); return 1
            timecodesFile = args_list[i]
        elif a in ('-j', '--json'):
            i += 1
            if i >= n_args:
                sys.stderr.write("No JSON file specified\n"); return 1
            jsonFile = args_list[i]
        elif scriptFilename is None and a and not a.startswith('-'):
            scriptFilename = a
        elif outputFilename is None and a and (a in ('-', '--') or not a.startswith('-')):
            outputFilename = a
        else:
            sys.stderr.write(f"Unknown argument: {a}\n")
            return 1
        i += 1

    if n_args == 0:
        mode = 'help'

    if mode in ('output', 'info', 'graph') and not scriptFilename:
        sys.stderr.write("No script file specified\n"); return 1
    if mode == 'output' and not outputFilename:
        sys.stderr.write("No output file specified\n"); return 1

    # ---- Import vpy4 API via PyCapsules ----
    _vspy_init_api_pointers()
    if import_vapoursynth():
        sys.stderr.write("Failed to import vapoursynth module\n")
        return 1

    # ---- Get VSAPI ----
    vsapi = vpy4_getVSAPI(VAPOURSYNTH_API_VERSION)
    if vsapi == NULL:
        sys.stderr.write("Failed to get VapourSynth API\n")
        return 1

    # ---- Version ----
    if mode == 'version':
        core = vsapi.createCore(0)
        if core == NULL:
            sys.stderr.write("Failed to create core\n")
            return 1
        vsapi.getCoreInfo(core, &coreInfo)
        sys.stdout.write(coreInfo.versionString.decode('utf-8'))
        vsapi.freeCore(core)
        return 0

    # ---- Help ----
    if mode == 'help':
        sys.stderr.write(HELP_TEXT)
        return 0

    # ---- Initialize VSScript policy ----
    if vpy4_initVSScript():
        sys.stderr.write("Failed to initialize VapourSynth scripting\n")
        return 1

    # ---- Creation flags ----
    if frameRefDebug:
        creationFlags |= ccfEnableFrameRefDebug
    if mode == 'graph' or filterTimeGraphFile is not None:
        creationFlags |= ccfEnableGraphInspection

    # ---- Create core ----
    core = vsapi.createCore(creationFlags)
    if core == NULL:
        sys.stderr.write("Failed to create core\n")
        return 1

    logHandle = vsapi.addLogHandler(
        <VSLogHandler>_log_handler, NULL, NULL, core)

    if printFilterTime or filterTimeGraphFile is not None:
        vsapi.setCoreNodeTiming(core, 1)

    # ---- Create script ----
    memset(&se, 0, sizeof(VSScript))
    se.core = core
    se.id = 2000
    se.setCWD = 1

    if vpy4_createScript(&se):
        err = vpy4_getError(&se)
        if err != NULL:
            sys.stderr.write(f"Script creation failed:\n{err.decode('utf-8', errors='replace')}\n")
        else:
            sys.stderr.write("Script creation failed\n")
        vsapi.freeCore(core)
        return 1

    # ---- Pass arguments ----
    if script_args:
        argsMap = vsapi.createMap()
        for key, val in script_args.items():
            key_b = key.encode('utf-8')
            val_b = val.encode('utf-8')
            vsapi.mapSetData(argsMap, key_b, val_b, len(val_b), dtUtf8, maAppend)
        vpy4_setVariables(&se, argsMap)
        vsapi.freeMap(argsMap)

    # ---- Evaluate script ----
    scriptEvalStart = time.monotonic()

    scriptFilenameBytes = os.path.abspath(scriptFilename).encode('utf-8')
    if vpy4_evaluateFile(&se, scriptFilenameBytes):
        err = vpy4_getError(&se)
        exitCode = se.exitCode
        if exitCode == 0:
            exitCode = 1
        if err != NULL:
            sys.stderr.write(f"Script evaluation failed:\n{err.decode('utf-8', errors='replace')}\n")
        else:
            sys.stderr.write("Script evaluation failed\n")
        vpy4_freeScript(&se)
        return exitCode

    scriptEvalTime = time.monotonic() - scriptEvalStart
    if printProgress:
        sys.stderr.write(f"Script evaluation done in {scriptEvalTime:.2f} seconds\n")

    core = vpy4_getCore(&se)

    # ---- Info mode ----
    if mode == 'info':
        numOutputs = vpy4_getAvailableOutputNodes(&se, 0, NULL)
        if numOutputs > 0:
            outputIndices = <int *>malloc(numOutputs * sizeof(int))
            vpy4_getAvailableOutputNodes(&se, numOutputs, outputIndices)
        try:
            infoCloseFile = False
            if outputFilename and outputFilename not in ('-', '--', '.'):
                outFile = open(outputFilename, 'wb')
                infoCloseFile = True
            else:
                outFile = sys.stdout.buffer if hasattr(sys.stdout, 'buffer') else sys.stdout
            first = True
            for idx in range(numOutputs):
                oIdx = outputIndices[idx]
                node = vpy4_getOutput(&se, oIdx)
                alphaNode = vpy4_getAlphaOutput(&se, oIdx)
                if node == NULL:
                    continue

                if not first:
                    outFile.write(b"\n")
                first = False

                nodeType = vsapi.getNodeType(node)
                if nodeType == mtVideo:
                    vi = vsapi.getVideoInfo(node)
                    outFile.write(f"Output Index: {oIdx}\nType: Video\n".encode())

                    if isConstantVideoFormat(vi):
                        outFile.write(f"Width: {vi.width}\nHeight: {vi.height}\n".encode())
                    else:
                        outFile.write(b"Width: Variable\nHeight: Variable\n")

                    outFile.write(f"Frames: {vi.numFrames}\n".encode())

                    if vi.fpsNum > 0 and vi.fpsDen > 0:
                        fps_val = <double>vi.fpsNum / <double>vi.fpsDen
                        outFile.write(f"FPS: {vi.fpsNum}/{vi.fpsDen} ({fps_val:.3f} fps)\n".encode())
                    else:
                        outFile.write(b"FPS: Variable\n")

                    if isConstantVideoFormat(vi):
                        vsapi.getVideoFormatName(&vi.format, formatName)
                        outFile.write(f"Format Name: {formatName.decode('utf-8')}\n".encode())
                        outFile.write(f"Color Family: {colorFamilyToString(vi.format.colorFamily)}\n".encode())
                        outFile.write(f"Alpha: {'Yes' if alphaNode != NULL else 'No'}\n".encode())
                        outFile.write(f"Sample Type: {'Float' if vi.format.sampleType == stFloat else 'Integer'}\n".encode())
                        outFile.write(f"Bits: {vi.format.bitsPerSample}\n".encode())
                        outFile.write(f"SubSampling W: {vi.format.subSamplingW}\n".encode())
                        outFile.write(f"SubSampling H: {vi.format.subSamplingH}\n".encode())
                    else:
                        outFile.write(b"Format Name: Variable\n")

                elif nodeType == mtAudio:
                    ai = vsapi.getAudioInfo(node)
                    vsapi.getAudioFormatName(&ai.format, formatName)
                    outFile.write(f"Output Index: {oIdx}\nType: Audio\n".encode())
                    outFile.write(f"Samples: {ai.numSamples}\n".encode())
                    outFile.write(f"Sample Rate: {ai.sampleRate}\n".encode())
                    outFile.write(f"Format Name: {formatName.decode('utf-8')}\n".encode())
                    outFile.write(f"Sample Type: {'Float' if ai.format.sampleType == stFloat else 'Integer'}\n".encode())
                    outFile.write(f"Bits: {ai.format.bitsPerSample}\n".encode())
                    outFile.write(f"Channels: {ai.format.numChannels}\n".encode())
                    outFile.write(f"Layout: {channelMaskToName(ai.format.channelLayout)}\n".encode())

                vsapi.freeNode(node)
                node = NULL
                if alphaNode != NULL:
                    vsapi.freeNode(alphaNode)
                    alphaNode = NULL
        finally:
            if infoCloseFile:
                outFile.close()
            if outputIndices != NULL:
                free(outputIndices)

        vpy4_freeScript(&se)
        return 0

    # ---- Get output node ----
    node = vpy4_getOutput(&se, outputIndex)
    if node == NULL:
        sys.stderr.write("Failed to retrieve output node. Invalid index specified?\n")
        vpy4_freeScript(&se)
        return 1

    alphaNode = vpy4_getAlphaOutput(&se, outputIndex)
    nodeType = vsapi.getNodeType(node)

    # Disable caches (no frame is ever requested twice)
    vsapi.setCacheMode(node, 0)
    if alphaNode != NULL:
        vsapi.setCacheMode(alphaNode, 0)

    # ---- Graph mode ----
    if mode == 'graph':
        if graphType == 'simple':
            graphMode = NodePrintMode_Simple
        else:
            graphMode = NodePrintMode_Full
        graphStr = printNodeGraph(graphMode, node, 0.0, vsapi).decode('utf-8')

        graphOutFile = None
        graphCloseFile = False
        if outputFilename and outputFilename not in ('-', '--', '.'):
            graphOutFile = open(outputFilename, 'w')
            graphCloseFile = True
        else:
            graphOutFile = sys.stdout

        graphOutFile.write(graphStr + "\n")
        if graphCloseFile:
            graphOutFile.close()

        vsapi.freeNode(node)
        if alphaNode != NULL:
            vsapi.freeNode(alphaNode)
        vpy4_freeScript(&se)
        return 0

    # ---- Apply start/end trim ----
    if startPos != 0 or endPos != -1:
        trimArgs = vsapi.createMap()
        vsapi.mapSetNode(trimArgs, b"clip", node, maAppend)
        if startPos != 0:
            vsapi.mapSetInt(trimArgs, b"first", startPos, maAppend)
        if endPos > -1:
            vsapi.mapSetInt(trimArgs, b"last", endPos, maAppend)

        stdPlugin = vsapi.getPluginByID(b"com.vapoursynth.std", core)
        if nodeType == mtVideo:
            trimResult = vsapi.invoke(stdPlugin, b"Trim", trimArgs)
        else:
            trimResult = vsapi.invoke(stdPlugin, b"AudioTrim", trimArgs)

        if vsapi.mapGetError(trimResult) != NULL:
            sys.stderr.write(f"Trim failed: {vsapi.mapGetError(trimResult).decode('utf-8', errors='replace')}\n")
            vsapi.freeMap(trimResult)
            vsapi.freeMap(trimArgs)
            vsapi.freeNode(node)
            if alphaNode != NULL:
                vsapi.freeNode(alphaNode)
            vpy4_freeScript(&se)
            return 1

        if alphaNode != NULL:
            vsapi.mapSetNode(trimArgs, b"clip", alphaNode, maReplace)
            alphaTrimResult = vsapi.invoke(stdPlugin, b"Trim", trimArgs)

        vsapi.freeMap(trimArgs)
        vsapi.freeNode(node)
        node = vsapi.mapGetNode(trimResult, b"clip", 0, &mapErr)
        vsapi.freeMap(trimResult)

        if alphaNode != NULL:
            vsapi.freeNode(alphaNode)
            alphaNode = vsapi.mapGetNode(alphaTrimResult, b"clip", 0, &mapErr)
            vsapi.freeMap(alphaTrimResult)

    # ---- Set up output file ----
    outFileObj = None
    closeOutFile = False
    tcFileObj = None
    jsonFileObj = None
    ftgFileObj = None

    if outputFilename in ('-', None, ''):
        try:
            import msvcrt, os as _os
            msvcrt.setmode(sys.stdout.fileno(), _os.O_BINARY)
        except Exception:
            pass
        outFileObj = sys.stdout.buffer if hasattr(sys.stdout, 'buffer') else sys.stdout
    elif outputFilename in ('--', '.'):
        outFileObj = None
    else:
        try:
            outFileObj = open(outputFilename, 'wb')
            closeOutFile = True
        except OSError as exc:
            sys.stderr.write(f"Failed to open output for writing: {exc}\n")
            vsapi.freeNode(node)
            if alphaNode != NULL:
                vsapi.freeNode(alphaNode)
            vpy4_freeScript(&se)
            return 1

    try:
        if timecodesFile:
            tcFileObj = open(timecodesFile, 'wb')
        if jsonFile:
            jsonFileObj = open(jsonFile, 'wb')
        if filterTimeGraphFile:
            ftgFileObj = open(filterTimeGraphFile, 'wb')
    except OSError as exc:
        sys.stderr.write(f"Failed to open auxiliary output file: {exc}\n")
        if closeOutFile and outFileObj is not None:
            outFileObj.close()
        vsapi.freeNode(node)
        if alphaNode != NULL:
            vsapi.freeNode(alphaNode)
        vpy4_freeScript(&se)
        return 1

    # ---- Set up output state ----
    data = _OutputState.__new__(_OutputState)
    data.vsapi = vsapi
    data.node = node
    data.alphaNode = alphaNode
    data.isVideo = (nodeType == mtVideo)
    data.fileobj = outFileObj
    data.timecodes_fileobj = tcFileObj
    data.json_fileobj = jsonFileObj
    data.printProgress = printProgress
    data.y4m = (container == 'y4m')
    data.condition = threading.Condition()

    # ---- Initialize output ----
    if data.isVideo:
        vi = vsapi.getVideoInfo(node)
        if not isConstantVideoFormat(vi):
            sys.stderr.write("Error: Cannot output clips with varying dimensions\n")
            vsapi.freeNode(node)
            if alphaNode != NULL:
                vsapi.freeNode(alphaNode)
            if closeOutFile and outFileObj is not None:
                outFileObj.close()
            vpy4_freeScript(&se)
            return 1
        data.totalFrames = vi.numFrames

        if container == 'y4m':
            if (vi.format.colorFamily != cfGray and vi.format.colorFamily != cfYUV) or alphaNode != NULL:
                sys.stderr.write("Error: can only apply y4m headers to YUV and Gray format clips without alpha\n")
                vsapi.freeNode(node)
                if alphaNode != NULL:
                    vsapi.freeNode(alphaNode)
                if closeOutFile and outFileObj is not None:
                    outFileObj.close()
                vpy4_freeScript(&se)
                return 1

            # Build Y4M header
            if vi.format.colorFamily == cfGray:
                y4mFmt = "mono"
                if vi.format.bitsPerSample > 8:
                    y4mFmt += str(vi.format.bitsPerSample)
            elif vi.format.colorFamily == cfYUV:
                if vi.format.subSamplingW == 1 and vi.format.subSamplingH == 1:
                    y4mFmt = "420"
                elif vi.format.subSamplingW == 1 and vi.format.subSamplingH == 0:
                    y4mFmt = "422"
                elif vi.format.subSamplingW == 0 and vi.format.subSamplingH == 0:
                    y4mFmt = "444"
                elif vi.format.subSamplingW == 2 and vi.format.subSamplingH == 2:
                    y4mFmt = "410"
                elif vi.format.subSamplingW == 2 and vi.format.subSamplingH == 0:
                    y4mFmt = "411"
                elif vi.format.subSamplingW == 0 and vi.format.subSamplingH == 1:
                    y4mFmt = "440"
                else:
                    sys.stderr.write("Error: no y4m identifier exists for current format\n")
                    vsapi.freeNode(node)
                    if closeOutFile and outFileObj is not None:
                        outFileObj.close()
                    vpy4_freeScript(&se)
                    return 1

                if vi.format.bitsPerSample > 8 and vi.format.sampleType == stInteger:
                    y4mFmt += f"p{vi.format.bitsPerSample}"
                elif vi.format.sampleType == stFloat:
                    y4mFmt += f"p{floatBitsToLetter(vi.format.bitsPerSample)}"

            header = (f"YUV4MPEG2 C{y4mFmt}"
                      f" W{vi.width} H{vi.height}"
                      f" F{vi.fpsNum}:{vi.fpsDen}"
                      f" Ip A0:0"
                      f" XLENGTH={vi.numFrames}\n").encode('ascii')
            if outFileObj is not None:
                outFileObj.write(header)

        elif container in ('wav', 'w64'):
            sys.stderr.write("Error: can't apply selected header type to video\n")
            vsapi.freeNode(node)
            if alphaNode != NULL:
                vsapi.freeNode(alphaNode)
            if closeOutFile and outFileObj is not None:
                outFileObj.close()
            vpy4_freeScript(&se)
            return 1

        if tcFileObj is not None:
            tcFileObj.write(b"# timecode format v2\n")
        if jsonFileObj is not None:
            jsonFileObj.write(b"[\n")

        data.ensureBuffer(vi.width * vi.height * vi.format.bytesPerSample)

    else:  # audio
        ai = vsapi.getAudioInfo(node)
        data.totalFrames = ai.numFrames
        data.totalSamples = ai.numSamples

        if container == 'wav':
            if not CreateWaveHeader(waveHdr, ai.format.sampleType == stFloat,
                                    ai.format.bitsPerSample, ai.sampleRate,
                                    ai.format.channelLayout, ai.numSamples):
                sys.stderr.write("Error: cannot create valid wav header\n")
                vsapi.freeNode(node)
                if closeOutFile and outFileObj is not None:
                    outFileObj.close()
                vpy4_freeScript(&se)
                return 1
            if outFileObj is not None:
                outFileObj.write((<uint8_t *>&waveHdr)[:sizeof(WaveHeader)])
        elif container == 'w64':
            if not CreateWave64Header(wave64Hdr, ai.format.sampleType == stFloat,
                                      ai.format.bitsPerSample, ai.sampleRate,
                                      ai.format.channelLayout, ai.numSamples):
                sys.stderr.write("Error: cannot create valid w64 header\n")
                vsapi.freeNode(node)
                if closeOutFile and outFileObj is not None:
                    outFileObj.close()
                vpy4_freeScript(&se)
                return 1
            if outFileObj is not None:
                outFileObj.write((<uint8_t *>&wave64Hdr)[:sizeof(Wave64Header)])
        elif container == 'y4m':
            sys.stderr.write("Error: can't apply selected header type to audio\n")
            vsapi.freeNode(node)
            if closeOutFile and outFileObj is not None:
                outFileObj.close()
            vpy4_freeScript(&se)
            return 1

        data.ensureBuffer(
            ai.format.numChannels * VS_AUDIO_FRAME_SAMPLES * ai.format.bytesPerSample)

    # ---- Run frame loop ----
    runStart = time.monotonic()

    outputNode(data, requests, core)

    elapsed = time.monotonic() - runStart

    # ---- Flush outputs ----
    if data.isVideo and jsonFileObj is not None and not data.outputError:
        jsonFileObj.write(b"]\n")
    if outFileObj is not None:
        try:
            outFileObj.flush()
        except Exception:
            pass
    if tcFileObj is not None:
        try:
            tcFileObj.flush()
        except Exception:
            pass
    if jsonFileObj is not None:
        try:
            jsonFileObj.flush()
        except Exception:
            pass

    # ---- Print summary ----
    if data.isVideo:
        fpsOut = data.totalFrames / elapsed if elapsed > 0 else 0.0
        sys.stderr.write(
            f"Output {data.totalFrames} frames in {elapsed:.2f} seconds"
            f" ({fpsOut:.2f} fps)\n")
    else:
        spsOut = ((data.totalFrames / elapsed * VS_AUDIO_FRAME_SAMPLES)
                  if elapsed > 0 else 0.0)
        sys.stderr.write(
            f"Output {data.totalSamples} samples in {elapsed:.2f} seconds"
            f" ({spsOut:.2f} sps)\n")

    result = 0
    if data.outputError:
        sys.stderr.write(data.errorMessage + "\n")
        result = 1

    # ---- Filter timing ----
    if result == 0:
        if printFilterTime:
            freedTime = vsapi.getFreedNodeProcessingTime(core, 0)
            timesStr = printNodeTimes(node, elapsed, freedTime, vsapi).decode('utf-8')
            sys.stderr.write(timesStr)

        if ftgFileObj is not None:
            graphTimed = printNodeGraph(
                NodePrintMode_FullWithTimes, node, elapsed, vsapi).decode('utf-8')
            try:
                ftgFileObj.write(graphTimed.encode('utf-8'))
            finally:
                ftgFileObj.close()
                ftgFileObj = None

    # ---- Cleanup ----
    if closeOutFile and outFileObj is not None:
        outFileObj.close()
    if tcFileObj is not None:
        tcFileObj.close()
    if jsonFileObj is not None:
        jsonFileObj.close()
    if ftgFileObj is not None:
        ftgFileObj.close()

    vsapi.freeNode(node)
    if alphaNode != NULL:
        vsapi.freeNode(alphaNode)

    if logHandle != NULL:
        vsapi.removeLogHandler(logHandle, core)

    vpy4_freeScript(&se)

    return result
