using UnityEngine;

/// <summary>
/// بيانات المراحل كنص ثابت — لاحقًا يمكن استبدالها بـ ScriptableObjects أو JSON من السيرفر.
/// </summary>
public static class LevelCatalog
{
    public readonly struct LevelSpec
    {
        public readonly string Question;
        public readonly string Choice0;
        public readonly string Choice1;
        public readonly string Choice2;
        public readonly int CorrectIndex;

        public LevelSpec(string question, string c0, string c1, string c2, int correctIndex)
        {
            Question = question;
            Choice0 = c0;
            Choice1 = c1;
            Choice2 = c2;
            CorrectIndex = Mathf.Clamp(correctIndex, 0, 2);
        }

        public string GetChoice(int index)
        {
            return index switch
            {
                0 => Choice0,
                1 => Choice1,
                _ => Choice2
            };
        }
    }

    private static readonly LevelSpec[] Levels =
    {
        new LevelSpec("أي كلمة مختلفة عن الباقي؟", "تفاح", "تفاح", "موز", 2),
        new LevelSpec("أي رقم مختلف؟", "3", "3", "7", 2),
        new LevelSpec("أي شكل مختلف؟", "●", "●", "■", 2),
        new LevelSpec("أي حرف مختلف؟", "ب", "ب", "ت", 2),
        new LevelSpec("أي لون (اسم) مختلف؟", "أزرق", "أزرق", "أخضر", 2),
        new LevelSpec("أي كلمة لا تنتمي لنفس الفئة؟", "سيارة", "حافلة", "تفاحة", 2),
        new LevelSpec("أي رمز مختلف؟", "▲", "▲", "▼", 2),
        new LevelSpec("أي عدد زوجي مختلف؟", "4", "8", "9", 2),
        new LevelSpec("أي كلمة بمعنى مختلف؟", "سعيد", "فرحان", "كرسي", 2),
        new LevelSpec("أي خيار يكسر التكرار؟", "1", "1", "2", 2)
    };

    public static int Count => Levels.Length;

    public static LevelSpec GetLevel(int index)
    {
        index = Mathf.Clamp(index, 0, Levels.Length - 1);
        return Levels[index];
    }
}
