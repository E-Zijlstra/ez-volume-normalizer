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

	static const Settings generic = Settings(
		"Generic",
		12, 12,
		1.2, 2.0,
		0,
		1000, 6,
		false,
	);

	static const Settings movie = Settings(
		"Movie",
		7, 8,
		1.4, 2.1,
		0,
		1200, 1,
		true,
	);

	static const Settings conference = Settings(
		"Online call",
		20, 10,
		-8.0, 1.3,
		200,
		800, 3,
		true,
	);

	static const Settings conference2 = Settings(
		"Conversation Flat",
		20, 10,
		-8.0, 1.3,
		20,
		200, 4,
		true,
	);

	static const Settings music = Settings(
		"Music",
		20, 30,
		1.7, 2.0,
		100,
		3000, 3,
		false,
	);

	static const Settings*[] all = [
		&generic,
		&movie,
		&conference,
		&music
	];
}

