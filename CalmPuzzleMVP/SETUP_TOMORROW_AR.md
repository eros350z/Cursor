# دليل مفصّل لباجر — تشغيل مشروع اللغز في Unity (من الصفر)

اقرأ بالترتيب. إذا توقفت عند خطوة وظهرت رسالة خطأ، انسخ نص الرسالة كاملًا وارسلها لي.

---

## أولًا: ماذا تنزل على جهازك؟

1. نزّل **Unity Hub** من موقع Unity الرسمي.
2. من داخل Unity Hub نزّل **محرك Unity** يُفضّل أن يكون **LTS** (مثل 2022.3 LTS أو أحدث LTS يظهر لك).
3. عند تثبيت المحرك، تأكد أنك اخترت على الأقل:
   - **Android Build Support** (إذا تبي تبني لأندرويد من جهازك)
   - **iOS Build Support** يظهر عادةً على **Mac** فقط (لأن iOS يحتاج Xcode)

> ملاحظة: **iOS** غالبًا يحتاج **Mac + Xcode** لاحقًا عند الرفع للستور. تقدر تبدأ التطوير على ويندوز، لكن بناء ملف iOS النهائي غالبًا على ماك.

---

## ثانيًا: إنشاء مشروع Unity جديد

1. افتح **Unity Hub** → **Projects** → **New project**.
2. اختر قالبًا مثل **2D (Built-In)** أو **2D (URP)** — أي **2D** يكفي لبداية المشروع.
3. سمّ المشروع مثلًا: `CalmPuzzleMVP`
4. اختر مكان المجلد على جهازك → **Create project**.
5. انتظر حتى يفتح المحرك بالكامل.

---

## ثالثًا: تفعيل TextMeshPro (مرة واحدة في المشروع)

1. من القائمة: **Window → TextMeshPro → Import TMP Essential Resources**
2. إذا ظهرت نافذة استيراد: اضغط **Import**

> بدون هذه الخطوة، غالبًا أي نص من نوع TextMeshPro يعطي تحذيرات أو ما يشتغل صح.

---

## رابعًا: نسخ ملفات المشروع من Git إلى Unity

1. في مستودع Git عندك، افتح مجلد: `CalmPuzzleMVP/DropInAssets/`
2. انسخ مجلد **`DropInAssets`** كاملًا إلى داخل مشروع Unity تحت:
   - `CalmPuzzleMVP/Assets/`
3. النتيجة يجب أن تصبح عندك مسارًا مثل:
   - `.../CalmPuzzleMVP/Assets/DropInAssets/Scripts/...`

> إذا نسخت بطريقة أخرى، المهم أن السكربتات تظهر داخل **Project** تحت `Assets` في Unity.

---

## خامسًا: إنشاء مشهد القائمة الرئيسية `MainMenu`

1. في Unity: **File → New Scene** (أو **Ctrl+N**)
2. احفظ المشهد: **File → Save As…**
3. سمّه **`MainMenu`** واحفظه داخل مجلد مثل:
   - `Assets/Scenes/MainMenu.unity`  
   (إذا ما عندك مجلد `Scenes` أنشئه بالزر يمين داخل Project)

### أضف زر التشغيل

1. في المشهد الفارغ: **GameObject → UI → Canvas**  
   (إذا طلب منك Unity إنشاء **EventSystem** وافق/أنشئه تلقائيًا)
2. **GameObject → UI → Button - TextMeshPro**  
3. غيّر نص الزر إلى مثلًا: **ابدأ**
4. أنشئ نص حالة (اختياري لكن مفيد):
   - **GameObject → UI → Text - TextMeshPro**
   - ضعه تحت الـ Canvas وسمّه `StatusText`

### أضف السكربت `MainMenuController`

1. **GameObject → Create Empty** وسمّه `MainMenuRoot`
2. من **Inspector** اضغط **Add Component** وابحث عن **`MainMenuController`**
3. اربط الحقول (Drag & Drop):
   - **Play Button**: اسحب كائن الزر الذي أنشأته
   - **Status Label**: اسحب `StatusText` (إن وُجد)
4. (اختياري لتجربة إعادة التقدم) أضف زر ثانٍ باسم **إعادة التقدم** واربطه في الحقل:
   - **Reset Progress Button**

5. في `MainMenuController` تأكد أن:
   - **Gameplay Scene Name** مكتوب فيه بالضبط: `Gameplay`  
     (نفس اسم ملف المشهد بدون `.unity`)

---

## سادسًا: إنشاء مشهد اللعب `Gameplay`

1. **File → New Scene** ثم احفظه:
   - `Assets/Scenes/Gameplay.unity`

### أنشئ واجهة اللعب

1. **GameObject → UI → Canvas**
2. تأكد أن عندك **EventSystem** في المشهد (إذا لا: **GameObject → UI → EventSystem**)

### نص السؤال

1. **GameObject → UI → Text - TextMeshPro**
2. سمّه `QuestionText`
3. كبّر الخط من Inspector ليكون واضحًا على الموبايل

### ثلاثة أزرار للإجابة

1. أنشئ زر: **GameObject → UI → Button - TextMeshPro** (كرر 3 مرات)
2. سمّهم مثلًا: `ChoiceA` `ChoiceB` `ChoiceC`
3. لكل زر: افتح الكائن الفرعي **Text (TMP)** واضبط المحاذاة/حجم الخط

### (اختياري) لوحة انتهاء

1. أنشئ **Panel** تحت Canvas وسمّه `CompletionPanel` وخليها **مخفية** أولًا (ألغِ تفعيل ✅ بجانب الاسم في الأعلى)
2. داخلها أضف **Text - TMP** للرسالة وسمّه `CompletionText`
3. داخلها أضف زر **رجوع للقائمة**

### أضف `GameplayController`

1. **GameObject → Create Empty** وسمّه `GameplayRoot`
2. **Add Component → GameplayController**
3. اربط الحقول:
   - **Question Label** → `QuestionText`
   - **Choice Buttons** يجب أن يكون طول المصفوفة 3:
     - Element 0 → `ChoiceA`
     - Element 1 → `ChoiceB`
     - Element 2 → `ChoiceC`
   - **Completion Panel** → `CompletionPanel` (إن أنشأتها)
   - **Completion Label** → `CompletionText`
   - **Back To Menu Button** → زر الرجوع
4. تأكد أن:
   - **Main Menu Scene Name** = `MainMenu`

> مهم: نصوص الخيارات على الأزرار **لا تحتاج تكتبها يدويًا**؛ السكربت يبحث عن `TextMeshProUGUI` داخل كل زر ويملأها تلقائيًا من `LevelCatalog`.

---

## سابعًا: إضافة المشاهد إلى Build Settings (ضروري جدًا)

1. **File → Build Settings**
2. اضغط **Add Open Scenes** إذا المشهد مفتوح، أو اسحب المشاهد من مجلد `Scenes` إلى النافذة.
3. رتّب الترتيب بحيث يكون:
   - **0**: `MainMenu`
   - **1**: `Gameplay`

> إذا الترتيب عكس، زر التشغيل قد يوديك للمشهد الغلط.

---

## ثامنًا: جرّب التشغيل داخل المحرك

1. افتح مشهد **`MainMenu`**
2. اضغط **Play ▶**
3. اضغط **ابدأ** → يفترض ينتقل إلى `Gameplay`
4. جاوب صح → يفترض ينتقل للمرحلة التالية تلقائيًا بعد لحظة بسيطة

---

## تاسعًا: إذا شيء ما اشتغل (أسباب شائعة)

- **زر ما يضغط**: تأكد أن **EventSystem** موجود في المشهد.
- **نصوص ما تظهر**: راجع استيراد **TMP Essential Resources**.
- **السكربت ما يظهر في Add Component**: تأكد أن السكربتات موجودة تحت `Assets/...` وأن Unity انتهى من التجميع **Compile** بدون أخطاء حمراء في **Console**.
- **المشهد ما ينتقل**: راجع أسماء المشاهد في السكربت (`MainMenu` و `Gameplay`) مطابقة لأسماء الملفات المحفوظة.

---

## عاشرًا: بعد ما يثبت عندك كل شيء

نكمل باجر على واحد من المسارات (اختر أنت):

1. **تحسين تجربة الموبايل** (Canvas Scaler، أحجام، RTL لاحقًا)
2. **تحدي يومي + غرفة عائلية بكود** (تصميم تقني + تدريج تنفيذ)
3. **AdMob + اشتراك** (بعد ما يثبت اللعب الأساسي)

---

بالتوفيق باجر. لما ترجع، اكتب لي: **نظام التشغيل (ويندوز/ماك)** + **إصدار Unity اللي نزلته** + **أول خطوة توقفت عندها** إن وقفت.
