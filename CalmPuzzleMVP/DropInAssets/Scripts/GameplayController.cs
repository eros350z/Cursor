using System.Collections;
using TMPro;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.UI;

/// <summary>
/// يربط واجهة اللعب بثلاثة أزرار + نص السؤال.
/// عيّن المراجع من المحرر: السؤال، ثلاثة أزرار، ولوحة اكتمال (اختياري).
/// </summary>
public class GameplayController : MonoBehaviour
{
    [SerializeField] private TextMeshProUGUI questionLabel;
    [SerializeField] private Button[] choiceButtons = new Button[3];
    [SerializeField] private GameObject completionPanel;
    [SerializeField] private TextMeshProUGUI completionLabel;
    [SerializeField] private Button backToMenuButton;
    [SerializeField] private string mainMenuSceneName = "MainMenu";

    private LevelCatalog.LevelSpec _current;
    private bool _locked;

    private void Awake()
    {
        if (completionPanel != null)
            completionPanel.SetActive(false);

        if (backToMenuButton != null)
            backToMenuButton.onClick.AddListener(() => SceneManager.LoadScene(mainMenuSceneName));
    }

    private void Start()
    {
        int total = LevelCatalog.Count;

        if (LevelProgressStore.HasFinishedAllLevels(total))
        {
            ShowCompletion("أحسنت! أكملت جميع المراحل المتوفرة حالياً.");
            _locked = true;
            return;
        }

        int levelIndex = LevelProgressStore.GetNextLevelIndex();
        _current = LevelCatalog.GetLevel(levelIndex);
        BindLevel(_current);
    }

    private void BindLevel(LevelCatalog.LevelSpec spec)
    {
        if (questionLabel == null || choiceButtons == null || choiceButtons.Length < 3)
        {
            Debug.LogError("GameplayController: عيّن questionLabel وثلاثة choiceButtons في المحرر.");
            return;
        }

        questionLabel.text = spec.Question;

        for (int i = 0; i < 3; i++)
        {
            int captured = i;
            var btn = choiceButtons[i];
            if (btn == null)
            {
                Debug.LogError($"GameplayController: choiceButtons[{i}] غير معيّن.");
                continue;
            }
            var label = btn.GetComponentInChildren<TextMeshProUGUI>(true);
            if (label != null)
                label.text = spec.GetChoice(i);

            btn.onClick.RemoveAllListeners();
            btn.onClick.AddListener(() => OnChoicePressed(captured));
        }
    }

    private void OnChoicePressed(int index)
    {
        if (_locked)
            return;

        if (index == _current.CorrectIndex)
        {
            _locked = true;
            StartCoroutine(WinRoutine());
        }
        else
        {
            if (questionLabel != null)
                questionLabel.text = "ليس هذا الخيار. حاول بهدوء…\n" + _current.Question;
        }
    }

    private IEnumerator WinRoutine()
    {
        yield return new WaitForSeconds(0.35f);
        LevelProgressStore.AdvanceAfterWin(LevelCatalog.Count);

        if (LevelProgressStore.HasFinishedAllLevels(LevelCatalog.Count))
            ShowCompletion("ممتاز! أنهيت آخر مرحلة في هذا الإصدار التجريبي.");
        else
            SceneManager.LoadScene(SceneManager.GetActiveScene().name);
    }

    private void ShowCompletion(string message)
    {
        if (completionPanel != null)
        {
            completionPanel.SetActive(true);
            if (completionLabel != null)
                completionLabel.text = message;
            return;
        }

        Debug.Log(message);
        StartCoroutine(ReturnToMenuAfterDelay(2f));
    }

    private IEnumerator ReturnToMenuAfterDelay(float seconds)
    {
        yield return new WaitForSeconds(seconds);
        SceneManager.LoadScene(mainMenuSceneName);
    }
}
