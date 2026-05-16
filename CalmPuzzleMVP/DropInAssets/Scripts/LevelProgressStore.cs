using UnityEngine;

/// <summary>
/// حفظ تقدم بسيط عبر PlayerPrefs — مناسب لـ MVP ثم يمكن استبداله بتخزين أقوى.
/// </summary>
public static class LevelProgressStore
{
    private const string NextLevelKey = "calm_puzzle_next_level_index";

    public static int GetNextLevelIndex()
    {
        return Mathf.Max(0, PlayerPrefs.GetInt(NextLevelKey, 0));
    }

    public static void SetNextLevelIndex(int index)
    {
        PlayerPrefs.SetInt(NextLevelKey, Mathf.Max(0, index));
        PlayerPrefs.Save();
    }

    /// <summary>بعد فوز اللاعب في مرحلة: يزيد المؤشر إن لم يتجاوز آخر مرحلة.</summary>
    public static void AdvanceAfterWin(int totalLevels)
    {
        int next = GetNextLevelIndex();
        if (next < totalLevels - 1)
            SetNextLevelIndex(next + 1);
        else
            SetNextLevelIndex(totalLevels);
    }

    public static bool HasFinishedAllLevels(int totalLevels)
    {
        return GetNextLevelIndex() >= totalLevels;
    }

    public static void ResetProgress()
    {
        PlayerPrefs.DeleteKey(NextLevelKey);
        PlayerPrefs.Save();
    }
}
