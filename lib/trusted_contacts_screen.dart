
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TrustedContact {
  final String id;
  final String name;
  final String phone;

  const TrustedContact({
    required this.id,
    required this.name,
    required this.phone,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
      };

  factory TrustedContact.fromJson(Map<String, dynamic> json) {
    return TrustedContact(
      id: json['id'].toString(),
      name: json['name'].toString(),
      phone: json['phone'].toString(),
    );
  }
}

class TrustedContactsScreen extends StatefulWidget {
  const TrustedContactsScreen({super.key});

  @override
  State<TrustedContactsScreen> createState() =>
      _TrustedContactsScreenState();
}

class _TrustedContactsScreenState
    extends State<TrustedContactsScreen> {
  static const String _storageKey = 'whisper_shield_trusted_contacts';

  List<TrustedContact> _contacts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_storageKey) ?? [];

      final contacts = saved.map((item) {
        return TrustedContact.fromJson(
          jsonDecode(item) as Map<String, dynamic>,
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _contacts = contacts;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('Could not load saved contacts.');
    }
  }

  Future<void> _saveContacts() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setStringList(
      _storageKey,
      _contacts.map((contact) => jsonEncode(contact.toJson())).toList(),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _editContact({TrustedContact? existing}) async {
    final nameController = TextEditingController(
      text: existing?.name ?? '',
    );
    final phoneController = TextEditingController(
      text: existing?.phone ?? '',
    );
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<TrustedContact>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          existing == null ? 'Add trusted contact' : 'Edit contact',
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Contact name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (value) =>
                    value == null || value.trim().isEmpty
                        ? 'Enter a name'
                        : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                keyboardType: TextInputType.phone,
                validator: (value) {
                  final phone = value?.trim() ?? '';
                  if (phone.length < 7 || phone.length > 20) {
                    return 'Enter a valid phone number';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;

              Navigator.pop(
                dialogContext,
                TrustedContact(
                  id: existing?.id ??
                      DateTime.now().microsecondsSinceEpoch.toString(),
                  name: nameController.text.trim(),
                  phone: phoneController.text.trim(),
                ),
              );
            },
            child: Text(existing == null ? 'Add' : 'Save'),
          ),
        ],
      ),
    );

    nameController.dispose();
    phoneController.dispose();

    if (result == null || !mounted) return;

    setState(() {
      final index = _contacts.indexWhere((c) => c.id == result.id);

      if (index == -1) {
        _contacts.add(result);
      } else {
        _contacts[index] = result;
      }
    });

    try {
      await _saveContacts();
      if (mounted) {
        _showMessage(
          existing == null ? 'Trusted contact added.' : 'Contact updated.',
        );
      }
    } catch (_) {
      _showMessage('Could not save contacts on this device.');
    }
  }

  Future<void> _deleteContact(TrustedContact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete contact?'),
        content: Text('Remove ${contact.name} from trusted contacts?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final previous = List<TrustedContact>.from(_contacts);

    setState(() {
      _contacts.removeWhere((c) => c.id == contact.id);
    });

    try {
      await _saveContacts();
      if (mounted) _showMessage('Contact deleted.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _contacts = previous);
      _showMessage('Could not delete contact.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trusted Contacts'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editContact(),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add contact'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _contacts.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.contacts_outlined,
                          size: 64,
                          color: Color(0xFF7C4DFF),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No trusted contacts yet',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Add people you trust so you can quickly '
                          'share your emergency message and location.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: () => _editContact(),
                          icon: const Icon(Icons.add),
                          label: const Text('Add first contact'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  itemCount: _contacts.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final contact = _contacts[index];

                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.person),
                        ),
                        title: Text(
                          contact.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(contact.phone),
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) {
                            if (action == 'edit') {
                              _editContact(existing: contact);
                            } else if (action == 'delete') {
                              _deleteContact(contact);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text('Edit'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
