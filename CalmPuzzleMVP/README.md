# Calm Puzzle MVP — Unity (Android + iOS)

هذا المجلد **ليس مشروع Unity كاملًا** (لا يوجد محرر Unity في بيئة السحابة)، لكنه يعطيك **أصولًا جاهزة** تنسخها إلى مشروع Unity جديد على جهازك وتبدأ منها فورًا.

## ما الذي تفعله على جهازك

1. ثبّت **Unity Hub** ثم محرك **Unity 2022.3 LTS** أو **6000.x LTS** (يفضّل LTS).
2. أنشئ مشروعًا جديدًا: **2D (URP أو Built-in حسب الافتراضي)**.
3. في المشروع: **Window → TextMeshPro → Import TMP Essential Resources** (مرة واحدة).
4. انسخ محتويات `DropInAssets/` إلى مجلد `Assets/` في مشروع Unity (دمج المجلدات).
5. أنشئ مشهدين:
   - `Assets/Scenes/MainMenu.unity` — كائن فارغ `MainMenu` وألحق به `MainMenuController`.
   - `Assets/Scenes/Gameplay.unity` — Canvas + **3 أزرار** (Button) + نص سؤال (TextMeshPro). أنشئ كائنًا فارغًا `Gameplay` وألحق به `GameplayController`، واسحب المراجع من الواجهة كما في التعليقات داخل السكربتات.
6. **File → Build Settings**: أضف `MainMenu` أولًا (index 0)، ثم `Gameplay` (index 1).

### تجميعة سريعة لمشهد Gameplay

- أنشئ `Canvas` + `EventSystem`.
- أضف `TextMeshPro - Text` للسؤال وسمّه مثلًا `QuestionText`.
- أنشئ 3 أزرار (`UI → Button - TextMeshPro`) وضع تحت كل زر نص TMP للخيار.
- أنشئ `Empty` باسم `GameplayRoot` وألحق `GameplayController` ثم اربط:
  - `questionLabel` → نص السؤال
  - `choiceButtons[0..2]` → الأزرار الثلاثة
  - (اختياري) `completionPanel` لوحة تحتوي نص اكتمال + زر عودة للقائمة، واربط `completionLabel` و`backToMenuButton`.
- في `MainMenu` ألحق `MainMenuController` بزر تشغيل واربط `playButton`، ويمكن إضافة زر اختياري `resetProgressButton` لمسح التقدم أثناء التجربة.

## iOS

للبناء والرفع على App Store ستحتاج عادةً **Mac + Xcode** لتوقيع التطبيق. Android يمكن من Windows/macOS/Linux.

## الخطوة التالية بعد MVP

- تحدي يومي، غرف عائلية، إعلانات (AdMob)، اشتراك — تضاف بعد استقرار اللعب والمشاهد.

## محتوى الكود الحالي

- تقدم مراحل محفوظ بـ `PlayerPrefs`.
- لغز بسيط قابل للتوسعة: **اختر العنصر المختلف** (ثلاث خيارات) مع أسئلة عربية جاهزة كنموذج.
