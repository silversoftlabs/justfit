enum OutfitOccasion { trabajo, casual, fiesta, deporte }

extension OutfitOccasionLabel on OutfitOccasion {
  String get label {
    switch (this) {
      case OutfitOccasion.trabajo:
        return 'Trabajo';
      case OutfitOccasion.casual:
        return 'Casual';
      case OutfitOccasion.fiesta:
        return 'Fiesta';
      case OutfitOccasion.deporte:
        return 'Deporte';
    }
  }
}

enum WeatherCondition { calor, frio, lluvia }

extension WeatherConditionLabel on WeatherCondition {
  String get label {
    switch (this) {
      case WeatherCondition.calor:
        return 'Calor';
      case WeatherCondition.frio:
        return 'Frío';
      case WeatherCondition.lluvia:
        return 'Lluvia';
    }
  }
}
