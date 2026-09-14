export const release = {
  version: "0.6.0",
  download:
    "https://github.com/Howell5/ziki/releases/download/v0.6.0/Ziki-0.6.0-macOS-arm64.dmg",
  notes: "https://github.com/Howell5/ziki/releases/tag/v0.6.0",
  repository: "https://github.com/Howell5/ziki",
};

export type Language = "en" | "zh";
type Copy = {
  nav: [string, string, string];
  skip: string;
  download: string;
  languageLabel: string;
  eyebrow: string;
  headline: [string, string];
  intro: string;
  watch: string;
  requirements: string;
  storyHint: string;
  storyTitle: string;
  story: string;
  storyFoot: string;
  close: string;
  artCaption: string;
  demoEyebrow: string;
  demoTitle: string;
  demoIntro: string;
  scenarios: [string, string];
  heard: string;
  written: string;
  sample: string;
  replay: string;
  stop: string;
  states: [string, string, string, string];
  examples: [
    { raw: string; result: string[] },
    { raw: string; result: string[] },
  ];
  methodEyebrow: string;
  methodTitle: string;
  steps: { title: string; text: string }[];
  principle: string;
  principleText: string;
  details: { title: string; text: string }[];
  faqTitle: string;
  faqs: { question: string; answer: string }[];
  endEyebrow: string;
  endTitle: string;
  endIntro: string;
  setup: string;
  notes: string;
  preview: string;
  footer: string;
  source: string;
};

export const copy: Record<Language, Copy> = {
  en: {
    nav: ["How it works", "The details", "Questions"],
    skip: "Skip to content",
    download: "Download for Mac",
    languageLabel: "切换到中文",
    eyebrow: "A LITTLE MORE UNDERSTANDING",
    headline: ["Speak freely.", "Write clearly."],
    intro:
      "Your thoughts don’t arrive perfectly written.\nThey don’t have to. Ziki turns natural speech into clear text, right where you work.",
    watch: "See it in action",
    requirements: "macOS 13+ · Apple Silicon · Bring your own API key",
    storyHint: "Why Ziki?",
    storyTitle: "Some things are understood, not just heard.",
    story:
      "In an old Chinese story, Boya played the qin and Ziqi heard the mountains and rivers in his music. He understood what lay beyond the notes. Their friendship gave us an enduring idea: zhiyin — someone who truly understands your voice.",
    storyFoot:
      "Ziki takes its name from Ziqi, and its inspiration from that kind of listening.",
    close: "Close the story",
    artCaption: "山水之间，得遇知音。",
    demoEyebrow: "FROM A THOUGHT TO A SENTENCE",
    demoTitle: "Your words. A little clearer.",
    demoIntro:
      "A task list when you need one. A natural sentence when you don’t.",
    scenarios: ["Planning work", "An everyday message"],
    heard: "WHAT YOU SAY",
    written: "WHAT YOU MEAN",
    sample: "Illustrative demo · No microphone access",
    replay: "Replay",
    stop: "Stop demo",
    states: [
      "Ready when you are",
      "Listening…",
      "Finding the words…",
      "Ready to use",
    ],
    examples: [
      {
        raw: "Okay, um, three things for the next release. First, fix that login bug. And, uh, we need a dark mode. Oh, and update the README too. The README, yeah.",
        result: ["Fix the login bug.", "Add dark mode.", "Update the README."],
      },
      {
        raw: "Hey, um, I’m running a little late. Maybe ten minutes, yeah, about ten. Go ahead and grab a table, and I’ll, I’ll meet you there.",
        result: [
          "Hey, I’m running about ten minutes late. Go ahead and grab a table, and I’ll meet you there.",
        ],
      },
    ],
    methodEyebrow: "LESS BETWEEN YOU AND YOUR WORDS",
    methodTitle: "One key. Keep your flow.",
    steps: [
      {
        title: "Press Fn. Say your piece.",
        text: "Start from the app you’re already in. Speak naturally, including the pauses and second thoughts.",
      },
      {
        title: "Finish speaking. Press Fn again.",
        text: "Ziki transcribes and tidies your words, using recent context to help make sense of what you mean.",
      },
      {
        title: "Back to what you were doing.",
        text: "The result lands in your text field. If direct insertion isn’t available, it’s ready on your clipboard.",
      },
    ],
    principle: "A better listener.\nNot a different voice.",
    principleText:
      "Good cleanup makes room for your meaning. It removes the “ums,” untangles repetition, and keeps your words feeling like yours.",
    details: [
      {
        title: "Context, not just keywords",
        text: "Recent dictation gives Ziki useful context for names and technical terms. Always give important details a quick check.",
      },
      {
        title: "Room to be heard",
        text: "Supported audio outputs are muted while you record, then restored. Your music or video keeps playing.",
      },
      {
        title: "A native Mac companion",
        text: "A small menu-bar app, a familiar keyboard shortcut, and local history. No new editor to move into.",
      },
      {
        title: "Your setup, in the open",
        text: "Connect your own Alibaba Cloud Bailian credentials. The source is available on GitHub; model usage is billed by your provider.",
      },
    ],
    faqTitle: "A few things worth knowing.",
    faqs: [
      {
        question: "What do I need to get started?",
        answer:
          "A Mac with Apple Silicon running macOS 13 or later, plus an Alibaba Cloud Bailian Workspace ID and API key. Install Ziki, enter your credentials, then follow the app’s microphone, Accessibility, and shortcut permission prompts. See the setup guide for the complete steps.",
      },
      {
        question: "Is everything processed on my Mac?",
        answer:
          "No. Speech recognition uses Bailian Fun-ASR, and text cleanup uses Qwen in the cloud. Audio and text are sent to the configured provider for processing. Final-text history is stored locally for 30 days. Audio is not saved locally by default; optional diagnostic recordings are retained for 7 days.",
      },
      {
        question: "Does Ziki rewrite everything as a list?",
        answer:
          "No. Tasks can become an ordered list, while messages stay natural prose. Ziki aims to remove filler and repetition without changing your intent. Like any AI tool, it can still mishear or edit incorrectly, so review names, numbers, and important messages before sending.",
      },
      {
        question: "Why might macOS show a security warning?",
        answer:
          "This release is a self-signed preview, not Apple-notarized. macOS may show a security warning. Only download from the official GitHub repository, verify the published checksums if needed, and read the installation guide before proceeding.",
      },
      {
        question: "Is Ziki free to use?",
        answer:
          "The Ziki source and downloadable build are available on GitHub. Cloud speech recognition and text cleanup use your own API credentials and may incur provider charges. The website demo is just a local illustration and does not call an AI service.",
      },
    ],
    endEyebrow: "LET YOUR THOUGHTS FIND THEIR WORDS",
    endTitle: "A little less typing.\nA little more you.",
    endIntro: "Made for the moments when saying it is easier.",
    setup: "Setup guide",
    notes: "Release notes",
    preview: "v0.6.0 · Self-signed preview · Not Apple-notarized",
    footer: "Inspired by listening. Built for expression.",
    source: "View source",
  },
  zh: {
    nav: ["如何使用", "产品细节", "常见问题"],
    skip: "跳转到正文",
    download: "下载 Mac 版",
    languageLabel: "Switch to English",
    eyebrow: "听见声音，也关心你的意思",
    headline: ["自在说，", "清楚写。"],
    intro:
      "想法不必一开始就井井有条。\n自然地说出来，Ziki 帮你整理成清楚的文字，落在你正在工作的地方。",
    watch: "看看它如何工作",
    requirements: "macOS 13+ · Apple Silicon · 需自备 API Key",
    storyHint: "名字从何而来？",
    storyTitle: "所听见的，不止于声音。",
    story:
      "伯牙抚琴，志在高山，子期便听见山的巍峨；志在流水，子期便听见水的浩荡。他听懂的，不只是琴音，还有琴音之外的心意。这便是「知音」。",
    storyFoot:
      "Ziki 的名字取意于子期。我们希望，好的倾听，也能发生在每一次表达之中。",
    close: "关闭品牌故事",
    artCaption: "山水之间，得遇知音。",
    demoEyebrow: "从一个念头，到一句好表达",
    demoTitle: "还是你的话，只是更清楚。",
    demoIntro: "交代任务时，条理分明。日常聊天时，自然就好。",
    scenarios: ["安排工作", "日常消息"],
    heard: "你自然地说",
    written: "整理后的表达",
    sample: "预设示例演示 · 不访问麦克风",
    replay: "再看一次",
    stop: "停止演示",
    states: ["准备好，随时开口", "正在聆听…", "正在整理表达…", "文字已就绪"],
    examples: [
      {
        raw: "那个，下个版本有三件事啊。先把那个登录的 bug 修一下。然后，呃，要加一个暗黑模式。哦对，还有 README 也更新一下，README 别忘了。",
        result: ["修复登录 bug。", "增加暗黑模式。", "更新 README。"],
      },
      {
        raw: "那个，我可能要晚一点，晚个十分钟吧，对，大概十分钟。你先找个位置坐，我到了就，就过来找你。",
        result: ["我可能会晚到十分钟。你先找个位置坐，我到了就过来找你。"],
      },
    ],
    methodEyebrow: "让表达，少一点费力",
    methodTitle: "一个按键，不打断思路。",
    steps: [
      {
        title: "按下 Fn，自然开口。",
        text: "不必切换应用，就在当前的输入位置开始。停顿、口头禅、临时改口，都可以先说出来。",
      },
      {
        title: "说完，再按一次 Fn。",
        text: "Ziki 将语音转成文字，结合近期口述的上下文，整理重复与语病，尽量保留你的原意。",
      },
      {
        title: "文字就位，继续手头的事。",
        text: "整理后的结果写入当前输入框。如果无法直接写入，文字也会放到剪贴板，方便粘贴。",
      },
    ],
    principle: "懂你的表达，\n不替你表达。",
    principleText:
      "去掉口头禅，理顺重复和停顿。好的整理，是让意思更清楚，而不是把你的话变成另一个人的口吻。",
    details: [
      {
        title: "联系上下文，不只听字面",
        text: "近期口述为人名、术语和话题提供参考。AI 仍可能听错，重要的信息值得再核对一眼。",
      },
      {
        title: "给声音留一点空间",
        text: "录音时将支持静音的音频输出暂时静音，结束后恢复原状态。音乐和视频继续播放，不必暂停。",
      },
      {
        title: "原生 Mac，安静相伴",
        text: "一个菜单栏应用，一个熟悉的快捷键，加上本地历史记录。无需搬进新的编辑器。",
      },
      {
        title: "自己的配置，公开的代码",
        text: "连接你自己的阿里云百炼凭据。源码公开可查，语音识别和文字整理的模型费用由服务商计费。",
      },
    ],
    faqTitle: "开始之前，你可能想知道。",
    faqs: [
      {
        question: "使用 Ziki 需要准备什么？",
        answer:
          "需要运行 macOS 13 或更高版本的 Apple Silicon Mac，以及阿里云百炼的 Workspace ID 和 API Key。安装后填写凭据，并按应用提示开启麦克风、辅助功能和快捷键所需权限。完整步骤请查看安装指南。",
      },
      {
        question: "所有内容都在本地处理吗？",
        answer:
          "不是。语音识别使用百炼 Fun-ASR，文字整理使用云端千问，音频和文字会发送到配置的服务商处理。最终文字历史保存在本地，保留 30 天；默认不在本地保存音频，开启诊断录音后保留 7 天。",
      },
      {
        question: "会把所有内容都改成编号列表吗？",
        answer:
          "不会。任务适合列成清单，聊天则保留自然段落。Ziki 尝试消除口头禅和重复，而不改变原意。AI 仍可能出现误听或不当改写，发送前请核对人名、数字和重要信息。",
      },
      {
        question: "为什么 macOS 可能显示安全提示？",
        answer:
          "当前版本采用自签名，尚未经过 Apple 公证，因此 macOS 可能显示安全提示。请仅从官方 GitHub 仓库下载，必要时核对公布的校验值，并先阅读安装指南。",
      },
      {
        question: "使用 Ziki 需要付费吗？",
        answer:
          "Ziki 的源码和安装包可在 GitHub 获取。云端语音识别和文字整理使用你自己的 API 凭据，可能产生服务商费用。官网上的演示只是本地预设示例，不会调用 AI 服务。",
      },
    ],
    endEyebrow: "让想法，自然成文",
    endTitle: "少一点敲打，\n多一点自在。",
    endIntro: "有些时候，说出来，就是更容易。",
    setup: "安装指南",
    notes: "更新说明",
    preview: "v0.6.0 · 自签名预览版 · 尚未经过 Apple 公证",
    footer: "始于倾听，成于表达。",
    source: "查看源码",
  },
};
