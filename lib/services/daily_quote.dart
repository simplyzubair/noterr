class DailyQuote {
  const DailyQuote._();

  static const _ayahs = [
    _Ayah('فَإِنَّ مَعَ الْعُسْرِ يُسْرًا', 'Ash-Sharh 94:5',
        'With hardship comes ease.'),
    _Ayah('وَاسْتَعِينُوا بِالصَّبْرِ وَالصَّلَاةِ', 'Al-Baqarah 2:45',
        'Seek help through patience and prayer.'),
    _Ayah('لَئِن شَكَرْتُمْ لَأَزِيدَنَّكُمْ', 'Ibrahim 14:7',
        'If you are grateful, I will surely increase you.'),
    _Ayah('وَأَن لَّيْسَ لِلْإِنسَانِ إِلَّا مَا سَعَى', 'An-Najm 53:39',
        'A person gains from what they strive for.'),
    _Ayah(
        'إِنَّ اللَّهَ لَا يُغَيِّرُ مَا بِقَوْمٍ حَتَّىٰ يُغَيِّرُوا مَا بِأَنفُسِهِمْ',
        'Ar-Ra\'d 13:11',
        'Allah changes a people when they change themselves.'),
    _Ayah('فَإِذَا عَزَمْتَ فَتَوَكَّلْ عَلَى اللَّهِ', 'Ali Imran 3:159',
        'When you decide, put your trust in Allah.'),
    _Ayah('وَمَن يَتَوَكَّلْ عَلَى اللَّهِ فَهُوَ حَسْبُهُ', 'At-Talaq 65:3',
        'Whoever trusts Allah, He is enough for them.'),
    _Ayah('إِنَّمَا يُوَفَّى الصَّابِرُونَ أَجْرَهُم بِغَيْرِ حِسَابٍ',
        'Az-Zumar 39:10', 'The patient are rewarded without measure.'),
    _Ayah('وَمَا تَوْفِيقِي إِلَّا بِاللَّهِ', 'Hud 11:88',
        'My success is only through Allah.'),
    _Ayah(
        'وَالَّذِينَ جَاهَدُوا فِينَا لَنَهْدِيَنَّهُمْ سُبُلَنَا',
        'Al-Ankabut 29:69',
        'Those who strive sincerely are guided to the way.'),
    _Ayah('وَتَوَاصَوْا بِالْحَقِّ وَتَوَاصَوْا بِالصَّبْرِ', 'Al-Asr 103:3',
        'Hold to truth and encourage patience.'),
    _Ayah('وَاصْبِرْ وَمَا صَبْرُكَ إِلَّا بِاللَّهِ', 'An-Nahl 16:127',
        'Be patient; your patience is only through Allah.'),
    _Ayah('رَّبِّ زِدْنِي عِلْمًا', 'Ta-Ha 20:114',
        'My Lord, increase me in knowledge.'),
    _Ayah('كُلٌّ يَعْمَلُ عَلَىٰ شَاكِلَتِهِ', 'Al-Isra 17:84',
        'Each person works according to their way.'),
    _Ayah('قَدْ أَفْلَحَ الْمُؤْمِنُونَ', 'Al-Mu\'minun 23:1',
        'Successful indeed are the believers.'),
    _Ayah('لِيَجْزِيَهُمُ اللَّهُ أَحْسَنَ مَا عَمِلُوا', 'An-Nur 24:38',
        'Allah rewards the best of what they did.'),
    _Ayah('فَامْشُوا فِي مَنَاكِبِهَا وَكُلُوا مِن رِّزْقِهِ', 'Al-Mulk 67:15',
        'Walk through the earth and seek His provision.'),
    _Ayah('وَاذْكُرِ اسْمَ رَبِّكَ وَتَبَتَّلْ إِلَيْهِ تَبْتِيلًا',
        'Al-Muzzammil 73:8', 'Remember your Lord and devote yourself to Him.'),
    _Ayah('إِنَّمَا نُطْعِمُكُمْ لِوَجْهِ اللَّهِ', 'Al-Insan 76:9',
        'Serve sincerely for the sake of Allah.'),
    _Ayah('وَنُيَسِّرُكَ لِلْيُسْرَى', 'Al-A\'la 87:8',
        'We will ease you toward ease.'),
    _Ayah('فَاذْكُرُونِي أَذْكُرْكُمْ', 'Al-Baqarah 2:152',
        'Remember Me; I will remember you.'),
    _Ayah('إِنَّ اللَّهَ مَعَ الصَّابِرِينَ', 'Al-Baqarah 2:153',
        'Allah is with the patient.'),
    _Ayah(
        'وَعَسَىٰ أَن تَكْرَهُوا شَيْئًا وَهُوَ خَيْرٌ لَّكُمْ',
        'Al-Baqarah 2:216',
        'You may dislike something while it is good for you.'),
    _Ayah('لَا يُكَلِّفُ اللَّهُ نَفْسًا إِلَّا وُسْعَهَا', 'Al-Baqarah 2:286',
        'Allah does not burden a soul beyond its capacity.'),
    _Ayah(
        'إِن تَنصُرُوا اللَّهَ يَنصُرْكُمْ وَيُثَبِّتْ أَقْدَامَكُمْ',
        'Muhammad 47:7',
        'Support Allah\'s cause; He supports you and steadies you.'),
    _Ayah('وَمَن يَتَّقِ اللَّهَ يَجْعَل لَّهُ مَخْرَجًا', 'At-Talaq 65:2',
        'Whoever is mindful of Allah, He makes a way out.'),
    _Ayah('سَيَجْعَلُ اللَّهُ بَعْدَ عُسْرٍ يُسْرًا', 'At-Talaq 65:7',
        'Allah will bring ease after hardship.'),
    _Ayah('إِنَّ مَعَ الْعُسْرِ يُسْرًا', 'Ash-Sharh 94:6',
        'Surely, with hardship comes ease.'),
    _Ayah('فَإِذَا فَرَغْتَ فَانصَبْ', 'Ash-Sharh 94:7',
        'When you finish, rise to the next task.'),
    _Ayah('وَإِلَىٰ رَبِّكَ فَارْغَب', 'Ash-Sharh 94:8',
        'Turn your longing toward your Lord.'),
  ];

  static const _quotes = [
    'Focus on the next right action.',
    'Small steps, done daily, become momentum.',
    'Protect your attention; it builds your life.',
    'Begin with gratitude. Continue with discipline.',
    'Clarity first, speed second.',
    'Do the useful thing before the urgent noise.',
    'A calm mind finishes better work.',
    'Today, simplify one thing.',
    'Progress is quiet before it is obvious.',
    'Let purpose choose your priorities.',
    'One completed task is better than ten worried thoughts.',
    'Work with intention, rest without guilt.',
    'Make the next step easy to start.',
    'Discipline is remembering what matters.',
    'Give your best attention to the present task.',
    'Peace grows where your actions match your values.',
    'Start small. Stay steady.',
    'Do less, but do it fully.',
    'Your future is built in today\'s habits.',
    'Write it down. Clear the mind.',
    'Consistency carries what motivation starts.',
    'Choose progress over perfection.',
    'Let the day have a direction.',
    'A focused hour can change the whole day.',
    'Be faithful with the work in front of you.',
    'Order outside begins with order inside.',
    'Finish the tiny promise.',
    'Less distraction, more devotion.',
    'Move with patience and purpose.',
    'The most important task deserves the quietest mind.',
    'Sabr is strength under control.',
    'Shukr turns today\'s work into worship.',
    'Make effort, then leave the outcome to Allah.',
    'Good work begins with a clean intention.',
    'A grateful heart works with lighter hands.',
    'Patience is not delay; it is steady movement.',
    'Barakah grows where focus and honesty meet.',
    'Do the task with ihsan: quietly, fully, well.',
    'Trust Allah, then do your part properly.',
    'Let your work be useful, sincere, and steady.',
    'A clear list turns worry into movement.',
    'Do the hard useful thing while your mind is fresh.',
    'Today does not need drama; it needs direction.',
    'Keep one promise to yourself before noon.',
    'The smallest finished task is real progress.',
    'Your attention is an amanah; spend it carefully.',
    'Make the next step so small that you can begin now.',
    'When motivation dips, return to routine.',
    'Strong days are built from honest minutes.',
    'Write it, do it, thank Allah for the ability.',
    'Do not chase every thought; choose the useful one.',
    'A quiet intention can carry heavy work.',
    'Reduce the list until action becomes obvious.',
    'The task in front of you is the doorway.',
    'Steady work beats anxious planning.',
    'Do one thing properly, then the next.',
    'Let your calendar reflect your values.',
    'Distraction is expensive; focus is barakah.',
    'Start before you feel ready.',
    'End the day with one clean completion.',
  ];

  static String forDate([DateTime? value]) {
    final date = value ?? DateTime.now();
    final localSlot = DateTime(
      date.year,
      date.month,
      date.day,
      (date.hour ~/ 6) * 6,
    );
    final slot = localSlot.difference(DateTime(2024)).inHours ~/ 6;
    final index = slot.abs();
    final ayah = _ayahs[index % _ayahs.length];
    final quote = _quotes[(index * 7) % _quotes.length];
    return '${ayah.arabic}\n${ayah.reference} - ${ayah.translation}\n$quote';
  }
}

class _Ayah {
  const _Ayah(this.arabic, this.reference, this.translation);

  final String arabic;
  final String reference;
  final String translation;
}
