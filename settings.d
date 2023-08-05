module settings;

struct Settings {
	string name;
	int avgLength;
	int numBars;
	float limiterOffset;
	float limiterWidth;
	int limiterAttack;
	int limiterHold;
	float limiterDecay;

	static const Settings generic = Settings(
		"Generic",
		15, 15,
		1.2, 2.0,
		0,
		1000, 6
	);

	static const Settings movie = Settings(
		"Movie",
		10, 10,
		1.5, 2.6,
		200,
		1500, 0.75
	);

	static const Settings conference = Settings(
		"Conversation",
		20, 10,
		-6.0, 1.3,
		50,
		500, 16
	);

	static const Settings music = Settings(
		"Music",
		20, 30,
		1.7, 2.0,
		100,
		3000, 3
	);

	static const Settings*[] all = [
		&generic,
		&movie,
		&conference,
		&music
	];
}

