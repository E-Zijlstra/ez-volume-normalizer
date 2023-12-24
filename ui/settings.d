module ui.settings;

struct Settings {
	string name;
	int avgLength;
	int numBars;
	float limiterOffset;
	float limiterWidth;
	int limiterAttack;
	int limiterHold;
	float limiterDecay;
	bool useWma;
	float resetDb;

	static const Settings generic = Settings(
		"Generic",
		12, 12,
		1.2, 2.0,
		0,
		1000, 6,
		false,
		-100,
	);

	static const Settings movie = Settings(
		"Movie",
		11, 9,
		1.4, 2.5,
		0,
		1200, 1.2,
		true,
		-11,
	);

	static const Settings conference = Settings(
		"Online call",
		20, 10,
		-8.0, 1.3,
		200,
		800, 3,
		true,
		-100,
	);

	static const Settings music = Settings(
		"Music",
		20, 30,
		1.7, 2.0,
		100,
		3000, 3,
		false,
		-20,
	);

	static const Settings*[] all = [
		&generic,
		&movie,
		&conference,
		&music
	];
}

