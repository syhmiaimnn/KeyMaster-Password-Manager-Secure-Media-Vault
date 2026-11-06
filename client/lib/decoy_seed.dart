import 'vault_data.dart';
import 'vault_item.dart';

/// What a new decoy vault holds: a few ordinary, harmless entries, so that
/// someone made to open the phone sees a vault that looks lived in.
///
/// Nothing here is real. The web addresses use the reserved example.com
/// family, which no one owns, and the passwords belong to no account. The
/// entries are given dates over the past months, not all "today".
class DecoySeed {
  const DecoySeed._();

  static VaultData build({DateTime? now}) {
    final today = now ?? DateTime.now();
    final items = <VaultItem>[];

    void add(
      String type,
      String title, {
      String username = '',
      String password = '',
      String website = '',
      String note = '',
      bool favorite = false,
      required int daysAgo,
    }) {
      final created = today.subtract(Duration(days: daysAgo));
      items.add(
        VaultItem(
          // Same style of id the editor makes, one per entry.
          id: '${created.microsecondsSinceEpoch + items.length}',
          type: type,
          title: title,
          username: username,
          password: password,
          website: website,
          note: note,
          favorite: favorite,
          createdAt: created,
          updatedAt: created,
        ),
      );
    }

    add('Password', 'Streaming account',
        username: 'family.movies@example.com',
        password: 'Sunday-Movies-2024',
        website: 'https://watch.example.com',
        favorite: true,
        daysAgo: 214);
    add('Password', 'Online shop',
        username: 'shopper.home@example.com',
        password: 'Basket#4471',
        website: 'https://shop.example.com',
        daysAgo: 160);
    add('Password', 'Library card',
        username: '2203 8841 07',
        password: 'bookworm2019',
        website: 'https://library.example.org',
        daysAgo: 301);
    add('Password', 'Gym membership',
        username: 'member.4821@example.com',
        password: 'Lift-Heavy-Things-8',
        website: 'https://gym.example.net',
        daysAgo: 96);
    add('Password', 'Recipe forum',
        username: 'home_cook',
        password: 'pasta-Night-77',
        website: 'https://recipes.example.com',
        daysAgo: 58);
    add('Password', 'Bus pass app',
        username: 'commuter@example.com',
        password: 'RideTheBus!23',
        website: 'https://transit.example.org',
        daysAgo: 25);
    add('Note', 'Shopping list',
        note: 'Milk\nEggs\nRice\nLight bulbs (E27)\nBirthday card',
        daysAgo: 9);
    add('Note', 'Guest Wi-Fi',
        note: 'Network: HomeGuest\nPassword: welcome-friends-2024',
        daysAgo: 120);

    return VaultData(items, const []);
  }
}
