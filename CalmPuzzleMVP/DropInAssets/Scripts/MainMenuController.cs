using TMPro;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.UI;

/// <summary>
/// شاشة بداية بسيطة: يعرض رقم المرحلة التالية ويحمّل مشهد اللعب.
/// </summary>
public class MainMenuController : MonoBehaviour
{
    [SerializeField] private Button playButton;
    [SerializeField] private TextMeshProUGUI statusLabel;
    [SerializeField] private string gameplaySceneName = "Gameplay";
    [SerializeField] private Button resetProgressButton;

    private void Awake()
    {
        if (playButton != null)
            playButton.onClick.AddListener(() => SceneManager.LoadScene(gameplaySceneName));

        if (resetProgressButton != null)
            resetProgressButton.onClick.AddListener(OnResetPressed);
    }

    private void Start()
    {
        RefreshStatus();
    }

    private void RefreshStatus()
    {
        if (statusLabel == null)
            return;

        int total = LevelCatalog.Count;
        if (LevelProgressStore.HasFinishedAllLevels(total))
        {
            statusLabel.text = "أكملت جميع المراحل. يمكنك إعادة التقدم من زر إعادة التجربة إن وُجد.";
            return;
        }

        int next = LevelProgressStore.GetNextLevelIndex();
        statusLabel.text = $"المرحلة التالية: {next + 1} من {total}";
    }

    private void OnResetPressed()
    {
        LevelProgressStore.ResetProgress();
        RefreshStatus();
    }
}
