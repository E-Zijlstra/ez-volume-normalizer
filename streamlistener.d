module streamlistener;

// windows.d from https://github.com/ZILtoid1991/iota
// CoCreateInstance : ole32.lib
import std.stdio;
import core.time;


import core.thread.osthread;
import core.sys.windows.com;
import core.sys.windows.windows;

import windows;
import util;

struct StreamListener {
	const capatureHz = 50;

	int bps;
	int sampleRate;
	int numChannels;
	float volumeDb;

	IAudioEndpointVolume endpointVolume;
	GUID volumeGuid;

	enum State {
		stopped, starting, running, stopping
	}

	shared {
		State state = State.stopped;
	}

	void stop() {
		if (state == State.stopped) return;

		state = State.stopping;
		while(state != State.stopped) {
			info(state);
		}
	}

	void setVolume(float v) {
		if (!endpointVolume) return;

		// endpointVolume.SetMasterVolumeLevelScalar(v, volumeGuid);
		import std.math;
		float db = 20 * log10(v);
		if (db < minDb) db = minDb;
		if (db > maxDb) db = maxDb;
		endpointVolume.SetMasterVolumeLevel(db, &volumeGuid);
	}

	float getVolumeDb() {
		if (!endpointVolume) return 0;
		endpointVolume.GetMasterVolumeLevel(volumeDb);
		return volumeDb;
	}

	private float minDb, maxDb, incDb;

	void loop(void delegate(float[], uint numFramesAvailable) blockProcessor) {
		state = State.starting;

		// Initialize the COM library
		CoInitialize(null);

		// Get a pointer to the default audio endpoint
		IMMDeviceEnumerator deviceEnumerator;
		uint res = CoCreateInstance(&CLSID_MMDeviceEnumerator, null, CLSCTX_ALL, &IID_IMMDeviceEnumerator, cast(void**)&deviceEnumerator);
		if (res != 0) return;

		IMMDevice speakers;
		deviceEnumerator.GetDefaultAudioEndpoint(EDataFlow.eRender, ERole.eConsole, speakers);
		if (speakers is null) return;

		speakers.Activate(IID_IAudioEndpointVolume, CLSCTX_ALL, null, cast(void**)&endpointVolume);
		if (res != 0) return;

		// get dB volume range		
		endpointVolume.GetVolumeRange(minDb, maxDb, incDb);
		info("Volume range: " ~ minDb.tos ~ " " ~ maxDb.tos ~ " " ~ incDb.tos);

		// Get a pointer to the audio client
		IAudioClient audioClient;
		speakers.Activate(IID_IAudioClient, CLSCTX_ALL, null, cast(void**)&audioClient);

		// Get the current audio format
		//# https://learn.microsoft.com/en-us/windows/win32/api/mmeapi/ns-mmeapi-waveformatex
		WAVEFORMATEX* format;
		audioClient.GetMixFormat(format);

		if (format.wFormatTag == WAVE_FORMAT_EXTENSIBLE) {
			WAVEFORMATEXTENSIBLE* format2 = cast(WAVEFORMATEXTENSIBLE*)format;
			if (format2.SubFormat != MEDIASUBTYPE_IEEE_FLOAT) return;
		}

		bps = format.wBitsPerSample;
		sampleRate = format.nSamplesPerSec;
		numChannels = format.nChannels;

		// Initialize the client
		const REFTIMES_PER_SEC = 1000_000_0;  // 1 unit == 100 nanoseconds
		int requestedDuration = REFTIMES_PER_SEC / capatureHz;
		info("Request duration " ~ requestedDuration.tos);
		res = audioClient.Initialize(AUDCLNT_SHAREMODE.AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_LOOPBACK, requestedDuration, 0, format, null);
		if (res != 0) return;

		// Get the buffer size
		uint bufferDuration;
		audioClient.GetBufferSize(bufferDuration);
		info("Got duration " ~ requestedDuration.tos);
		if (bufferDuration == 0) return;

		// Get a pointer to the audio capture client
		IAudioCaptureClient captureClient;
		res = audioClient.GetService(IID_IAudioCaptureClient, cast(void**)&captureClient);
		if (res != 0) return;
		if (captureClient is null) return;

		// Start recording
		audioClient.Start();
		info("listening");
		float[] dummy;
		try {
			blockProcessor(dummy, 0);
		}
		catch(Error e) {
			info(e.message);
		}

		uint numFramesAvailable = 0;
		int sleepUs = 5;
		int idleCount;
		state = State.running;
		while (state == State.running) {
			//Thread.sleep(dur!"msecs"(1));
			if (sleepUs > 0) Thread.sleep(dur!"usecs"(sleepUs));

			// Get the next packet of data
			captureClient.GetNextPacketSize(numFramesAvailable);
			if (numFramesAvailable == 0) {
				idleCount++;
				continue;
			}

			if (idleCount > 100) sleepUs++;
			if (idleCount == 0 && sleepUs > 0) sleepUs--;
			idleCount = 0;

			// Get a pointer to the data
			BYTE* data;
			DWORD pdwFlags; // buffer-status flags. The method writes either 0 or the bitwise-OR combination SILENT/DISCONTINUITY/TIMESTAMP_ERROR
			captureClient.GetBuffer(data, numFramesAvailable, pdwFlags, null, null);

			float[] fdata = (cast(float*) data)[0..numFramesAvailable * numChannels];
			blockProcessor(fdata, numFramesAvailable);

			captureClient.ReleaseBuffer(numFramesAvailable);

		}

		// Stop recording
		audioClient.Stop();

		// Release the audio client
		audioClient.Release();

		// Release the speakers
		speakers.Release();

		// Release the device enumerator
		deviceEnumerator.Release();

		// Uninitialize the COM library
		CoUninitialize();
		state = State.stopped;
	}
}