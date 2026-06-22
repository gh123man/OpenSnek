import Foundation
import OpenSnekCore
import OpenSnekProtocols

extension OpenSnekProbe {
  static var usageText: String {
    """
    Usage:
      OpenSnekProbe dpi-read
      OpenSnekProbe dpi-set --values 1600,6400 [--active 1]
      OpenSnekProbe dpi-cycle --sequence 800,6400;1600,6400 --loops 10 [--active 1] [--sleep-ms 120]
      OpenSnekProbe bt-info
      OpenSnekProbe bt-raw-read --key 10840000 [--name "BSK V3 PRO"] [--timeout-ms 600]
      OpenSnekProbe bt-raw-write --key 10040000 --payload 0400000000ff4010 [--name "BSK V3 PRO"] [--timeout-ms 900]
      OpenSnekProbe bt-profile-read [--stored-slots 1,2,3,4] [--button-slots 5,106] [--include-live-buttons on|off] [--name "BSK V3 PRO"]
      OpenSnekProbe bt-profile-active-set --target 3 --yes [--name "BSK V3 PRO"]
      OpenSnekProbe bt-profile-create --stored-slot 1 --profile-name OPENSNEK_MAC_SLOT_1 --yes [--name "BSK V3 PRO"]
      OpenSnekProbe bt-profile-button-read --stored-slot 1 --button-slot 5 [--name "BSK V3 PRO"]
      OpenSnekProbe bt-profile-button-set --stored-slot 1 --button-slot 5 [--kind keyboard_simple] [--hid-key 0x09] [--clutch-dpi 800] [--project-live on|off] --yes [--name "BSK V3 PRO"]
      OpenSnekProbe bt-profile-hid-watch [--pid 0x00ac] [--name "BSK V3 PRO"] [--duration 20] [--max-reports 0]
      OpenSnekProbe bt-profile-watch [--name "BSK V3 PRO"] [--slot 4] [--poll-ms 1000] [--samples 20] [--timeout-ms 900]
      OpenSnekProbe bt-lighting-info [--zone all|scroll_wheel|logo|underglow] [--name "BSK V3 PRO"]
      OpenSnekProbe bt-lighting-read [--zone all|scroll_wheel|logo|underglow] [--name "BSK V3 PRO"]
      OpenSnekProbe bt-lighting-brightness --value 128 [--zone all|scroll_wheel|logo|underglow] [--name "BSK V3 PRO"]
      OpenSnekProbe bt-lighting-color --color ff6600 [--zone all|scroll_wheel|logo|underglow] [--name "BSK V3 PRO"]
      OpenSnekProbe usb-info [--pid 0x00ab]
      OpenSnekProbe usb-battery-read [--pid 0x00ab]
      OpenSnekProbe usb-lighting-info [--zone all|scroll_wheel|logo|underglow] [--pid 0x00ab]
      OpenSnekProbe usb-lighting-read [--zone all|scroll_wheel|logo|underglow] [--pid 0x00ab]
      OpenSnekProbe usb-lighting-brightness --value 128 [--zone all|scroll_wheel|logo|underglow] [--pid 0x00ab]
      OpenSnekProbe usb-lighting-effect --kind static [--color 00ff00] [--secondary ff00ff] [--direction left|right] [--speed 2] [--zone all|scroll_wheel|logo|underglow] [--pid 0x00ab]
      OpenSnekProbe usb-lighting-frame --colors ff0000,00ff00,0000ff [--start-col 0] [--row 0] [--storage 0x01] [--pid 0x00aa]
      OpenSnekProbe usb-lighting-concurrency [--mode locked|unlocked|both] [--frames 90] [--commands 30] [--interval-ms 33] [--response-delay-us 1000] [--pid 0x00ab]
      OpenSnekProbe usb-profile-read [--profiles 2,3,4,5] [--button-slots 5,106] [--include-effective on|off] [--pid 0x00ab]
      OpenSnekProbe usb-profile-active-read [--pid 0x00ab]
      OpenSnekProbe usb-profile-active-set --profile 3 --yes [--pid 0x00ab]
      OpenSnekProbe usb-profile-verify-writes --profile 5 --yes [--pid 0x00ab]
      OpenSnekProbe usb-profile-verify-changed-writes --profile 5 --yes [--pid 0x00ab]
      OpenSnekProbe usb-profile-clone --source-profile 5 --target-profile 4 [--metadata repair|exact] [--target-name NAME] [--target-uuid UUID] [--button-slots 5] [--content on|off] --yes [--pid 0x00ab]
      OpenSnekProbe usb-profile-verify-metadata-write [disabled: needs guarded content rewrite/readback flow]
      OpenSnekProbe usb-profile-delete --profile 2 --yes [--pid 0x00ab]
      OpenSnekProbe usb-input-listen [--pid 0x00ab] [--duration 15] [--max-reports 0]
      OpenSnekProbe usb-input-values [--pid 0x00ab] [--duration 15] [--max-reports 0]
      OpenSnekProbe usb-button-read --slot 4 [--profile default|direct|both] [--pid 0x00ab]
      OpenSnekProbe usb-button-set --slot 4 --kind right_click [--profile both] [--hid-key 4] [--turbo on|off] [--turbo-rate 142] [--clutch-dpi 400] [--pid 0x00ab]
      OpenSnekProbe usb-button-set-raw --slot 4 --hex 01010200000000 [--profile default|direct|both] [--pid 0x00ab]
      OpenSnekProbe usb-raw --class 0x02 --cmd 0x8C --size 0x0A [--args 01,04,00,00,00,00,00,00,00,00] [--pid 0x00ab]

    USB button kinds:
      default dpi_cycle dpi_clutch left_click right_click middle_click scroll_up scroll_down mouse_back mouse_forward keyboard_simple clear_layer

    USB lighting kinds:
      off static spectrum wave reactive pulse_random pulse_single pulse_dual
    """
  }

}
