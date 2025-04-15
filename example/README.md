# Hydrated MobX Example

This is a simple example demonstrating how to use the `hydrated_mobx` package for state persistence in Flutter applications.

## Features

- Counter state persistence using MobX
- Automatic state restoration on app restart
- Clean and simple implementation

## Getting Started

1. Make sure you have Flutter installed and set up
2. Clone this repository
3. Navigate to the example directory
4. Run `flutter pub get` to install dependencies
5. Run `flutter pub run build_runner build` to generate MobX code
6. Run the app with `flutter run`

## How it Works

The example demonstrates a simple counter app where the count is persisted between app restarts. The persistence is handled automatically by the `hydrated_mobx` package.

Key components:

- `CounterStore`: A MobX store that extends `HydratedMobx` for automatic persistence
- `main.dart`: Sets up the app and initializes the storage
- `counter_store.dart`: Contains the business logic and state management

## Usage

To use `hydrated_mobx` in your own project:

1. Extend `HydratedMobx` for your store
2. Implement `toJson` and `fromJson` methods
3. Initialize the storage in your `main.dart`
4. Use the store as you would any other MobX store

## License

This project is licensed under the MIT License - see the LICENSE file for details. 