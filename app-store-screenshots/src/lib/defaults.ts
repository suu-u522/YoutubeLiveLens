import { DEFAULT_LOCALE } from "./locale";
import type { Device, ProjectState, Slide } from "./types";

let _id = 0;
export const nid = () => `s_${Date.now().toString(36)}_${(_id++).toString(36)}`;

const en = (s: string) => ({ [DEFAULT_LOCALE]: s });

function makeStarterSlides(): Slide[] {
  return [
    {
      id: nid(),
      layout: "hero",
      label: en("ライブチャット分析"),
      headline: en("盛り上がりを\n見逃さない"),
      screenshot: "/screenshots/apple/iphone/en/01.png",
    },
    {
      id: nid(),
      layout: "device-bottom",
      label: en("URL入力"),
      headline: en("URLを貼るだけで\nすぐ分析"),
      screenshot: "/screenshots/apple/iphone/en/02.png",
    },
    {
      id: nid(),
      layout: "device-top",
      label: en("分析結果"),
      headline: en("神回の瞬間が\n一目でわかる"),
      screenshot: "/screenshots/apple/iphone/en/03.png",
      inverted: true,
    },
    {
      id: nid(),
      layout: "device-bottom",
      label: en("コメント検索"),
      headline: en("コメントを\nキーワードで探す"),
      screenshot: "/screenshots/apple/iphone/en/04.png",
    },
  ];
}

function ipadStarter(): Slide[] {
  return [
    {
      id: nid(),
      layout: "hero",
      label: en("MEET YOUR APP"),
      headline: en("Made for\nthe big screen."),
      screenshot: "",
    },
    {
      id: nid(),
      layout: "device-bottom",
      label: en("FEATURE 01"),
      headline: en("Built for\nfocus."),
      screenshot: "",
    },
    {
      id: nid(),
      layout: "device-top",
      label: en("FEATURE 02"),
      headline: en("Always within reach."),
      screenshot: "",
      inverted: true,
    },
  ];
}

function tabletStarter(kind: "7" | "10"): Slide[] {
  return [
    {
      id: nid(),
      layout: "hero",
      label: en("MEET YOUR APP"),
      headline: en(kind === "7" ? "Pocket-sized\npower." : "Made for\nthe big screen."),
      screenshot: "",
    },
    {
      id: nid(),
      layout: "split-landscape",
      label: en("FEATURE 01"),
      headline: en("Wide canvas,\nbigger ideas."),
      screenshot: "",
    },
  ];
}

function fgStarter(): Slide[] {
  return [
    {
      id: nid(),
      layout: "feature-graphic",
      label: {},
      headline: en("Your tagline goes here."),
      screenshot: "",
    },
  ];
}

export const DEFAULT_PROJECT: ProjectState = {
  appName: "LiveLens",
  themeId: "clean-light",
  locales: [DEFAULT_LOCALE],
  locale: DEFAULT_LOCALE,
  device: "iphone",
  orientation: "portrait",
  appIcon: "/app-icon.png",
  slidesByDevice: {
    iphone: makeStarterSlides(),
    android: makeStarterSlides(),
    ipad: ipadStarter(),
    "android-7": tabletStarter("7"),
    "android-10": tabletStarter("10"),
    "feature-graphic": fgStarter(),
  },
};

export function newSlide(layout: Slide["layout"] = "device-bottom"): Slide {
  return {
    id: nid(),
    layout,
    label: en("NEW"),
    headline: en("Edit this\nheadline."),
    screenshot: "",
  };
}

export function detectPlatform(device: Device): "ios" | "android" {
  return device === "iphone" || device === "ipad" ? "ios" : "android";
}
