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

struct StreamEndpoint {
	string id;
	string name;
	bool isDefault;
}

struct StreamListener {
	const capatureHz = 50;

	int bps;
	int sampleRate;
	int numChannels;
	float volumeDb;
	float requestedDb;
	string deviceId;
	float minDb, maxDb, incDb;
	bool highQuality = false;

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

	import std.math;

	void setVolume(float v) {
		// endpointVolume.SetMasterVolumeLevelScalar(v, volumeGuid);
		float db = 20 * log10(v);
		setVolumeDb(db);
	}

	void setVolumeDb(float db) {
		if (!endpointVolume) return;

		if (db < minDb) db = minDb;
		if (db > maxDb) db = maxDb;
		if (abs(requestedDb-db)<0.5f) return;
		requestedDb = db;
		endpointVolume.SetMasterVolumeLevel(db, &volumeGuid);
	}

	float getVolumeDb() {
		if (!endpointVolume) return 0;
		endpointVolume.GetMasterVolumeLevel(volumeDb);
		return volumeDb;
	}


	StreamEndpoint[] getEndpoints() {
		import std.conv;
		import core.sys.windows.objidl;

		StreamEndpoint[] endpoints;
		CoInitialize(null);

		// Get a pointer to the default audio endpoint
		IMMDeviceEnumerator deviceEnumerator;
		uint res = CoCreateInstance(&CLSID_MMDeviceEnumerator, null, CLSCTX_ALL, &IID_IMMDeviceEnumerator, cast(void**)&deviceEnumerator);
		if (res != 0) return endpoints;

		// List all endpoints
		wchar* zId;
		IMMDevice defaultDevice;
		deviceEnumerator.GetDefaultAudioEndpoint(EDataFlow.eRender, ERole.eConsole, defaultDevice);
		defaultDevice.GetId(zId);
		string defaultId = to!string(zId);
		defaultDevice.Release();
		//deviceId = defaultId;

		IMMDeviceCollection pCollection;
		deviceEnumerator.EnumAudioEndpoints(EDataFlow.eRender, DEVICE_STATE_ACTIVE, pCollection);
		uint numDevices;
		pCollection.GetCount(numDevices);
		for(uint i =0; i < numDevices; i++) {
			IMMDevice device;
			pCollection.Item(i, device);
			device.GetId(zId);
			//info("Device " ~ i.tos ~ " " ~ to!string(zId));
			IPropertyStore propertyStore;
			device.OpenPropertyStore(STGM_READ, propertyStore);
			PROPVARIANT prop;
			// DEVPKEY_Device_FriendlyName => PA24A (NVIDIA High Definition Audio)
			// DEVPKEY_Device_DeviceDesc => PA24A
			// DEVPKEY_DeviceInterface_FriendlyName => NVIDIA High Definition Audio
			propertyStore.GetValue(DEVPKEY_Device_DeviceDesc, prop);
			//info("Device " ~ i.tos ~ " " ~ to!string(prop.pwszVal));
			endpoints ~= StreamEndpoint(to!string(zId), to!string(prop.pwszVal), defaultId == to!string(zId));
			propertyStore.Release();
			device.Release();
		}
		pCollection.Release();

		deviceEnumerator.Release();
		CoUninitialize();

		return endpoints;
	}


	void loop(void delegate(float[], uint numFramesAvailable) blockProcessor) {
		state = State.starting;

		// Initialize the COM library
		CoInitialize(null);

		// Get a pointer to the default audio endpoint
		IMMDeviceEnumerator deviceEnumerator;
		uint res = CoCreateInstance(&CLSID_MMDeviceEnumerator, null, CLSCTX_ALL, &IID_IMMDeviceEnumerator, cast(void**)&deviceEnumerator);
		if (res != 0) return;

		IMMDevice device;
		//deviceEnumerator.GetDefaultAudioEndpoint(EDataFlow.eRender, ERole.eConsole, device);
		import std.utf;
		const(wchar)* wcId = deviceId.toUTF16z;
		deviceEnumerator.GetDevice(wcId, &device);
		if (device is null) return;

		device.Activate(IID_IAudioEndpointVolume, CLSCTX_ALL, null, cast(void**)&endpointVolume);
		if (res != 0) return;

		// get dB volume range		
		endpointVolume.GetVolumeRange(minDb, maxDb, incDb);
		info("Volume range: " ~ minDb.tos ~ " " ~ maxDb.tos ~ " " ~ incDb.tos);

		// Get a pointer to the audio client
		IAudioClient audioClient;
		device.Activate(IID_IAudioClient, CLSCTX_ALL, null, cast(void**)&audioClient);

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
		info("Request duration ", requestedDuration.tos);
		res = audioClient.Initialize(AUDCLNT_SHAREMODE.AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_LOOPBACK, requestedDuration, 0, format, null);
		if (res != 0) return;

		// Get the buffer size
		uint bufferDuration;
		audioClient.GetBufferSize(bufferDuration);
		info("Got buffersize ", bufferDuration);
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
		catch(Throwable t) {
			info("******* stream exception *******");
			info(t.message);
			info(t.file);
			info(t.info);
		}

		state = State.running;
		while (state == State.running) {
			// Get the next packet of data
			uint numFramesAvailable = 0;
			captureClient.GetNextPacketSize(numFramesAvailable);
			if (numFramesAvailable == 0) {
				if (!highQuality) Thread.sleep(usecs(1)); // Sleeping here is the optimal place. It stil may miss a few samples (<40/s) but that's better than having 20% cpu usage.
				continue;
			}

			// Get a pointer to the data
			BYTE* data;
			DWORD pdwFlags; // buffer-status flags. The method writes either 0 or the bitwise-OR combination SILENT/DISCONTINUITY/TIMESTAMP_ERROR
			captureClient.GetBuffer(data, numFramesAvailable, pdwFlags, null, null);

			float[] fdata = (cast(float*) data)[0..numFramesAvailable * numChannels];
			blockProcessor(fdata, numFramesAvailable);

			captureClient.ReleaseBuffer(numFramesAvailable);
		}

		audioClient.Stop();		// Stop recording
		audioClient.Release();
		device.Release();
		deviceEnumerator.Release();
		CoUninitialize();		// Uninitialize the COM library
		state = State.stopped;
	}
}