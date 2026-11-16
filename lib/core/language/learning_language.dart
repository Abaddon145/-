const activeLanguageSettingKey = 'active_language';

String normalizeLearningLanguage(String? value) => value == 'en' ? 'en' : 'ko';

String scopedSetting(String language, String key) =>
    '${normalizeLearningLanguage(language)}:$key';

String checkinSettingKey(String language, String day) =>
    'checkin:${normalizeLearningLanguage(language)}:$day';

String objectiveSettingKey(String language, String day) =>
    'objective:${normalizeLearningLanguage(language)}:$day';
