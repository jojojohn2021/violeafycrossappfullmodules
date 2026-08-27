import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/file_download_helper.dart';
import '../../../models/models.dart';
import '../../../providers/app_providers.dart';

/// Amazon-style tax invoice preview for a single order, with share/print/download actions.
class InvoiceScreen extends ConsumerStatefulWidget {
  final SalesOrder order;

  const InvoiceScreen({super.key, required this.order});

  @override
  ConsumerState<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends ConsumerState<InvoiceScreen> {
  late final Future<Uint8List> _pdfFuture;
  Uint8List? _cachedPdfBytes;
  List<Map<String, dynamic>> _invoiceItems = const [];
  Map<String, dynamic> _invoiceData = const {};

  String get _fileName => 'Invoice_${widget.order.orderNumber.isNotEmpty ? widget.order.orderNumber : widget.order.id}.pdf';

  @override
  void initState() {
    super.initState();
    _pdfFuture = _buildPdf();
  }

  Future<Uint8List> _buildPdf() async {
    if (_cachedPdfBytes != null) {
      return _cachedPdfBytes!;
    }
    final repo = ref.read(shoppingRepositoryProvider);
    final invoice = await repo.getInvoice(widget.order.id);
    _invoiceData = invoice;
    final header = Map<String, dynamic>.from(invoice['header'] as Map? ?? const {});
    final summary = Map<String, dynamic>.from(invoice['summary'] as Map? ?? const {});
    final referral = Map<String, dynamic>.from(invoice['referralSummary'] as Map? ?? const {});
    final invoiceItems = (invoice['items'] as List? ?? const []).map((item) => Map<String, dynamic>.from(item as Map)).toList();
    _invoiceItems = invoiceItems;
    final doc = pw.Document();
    final address = widget.order.shippingAddress;
    final invoiceId = invoice['invoiceId']?.toString() ?? widget.order.id;
    final subtotal = (summary['subtotal'] as num?)?.toDouble() ?? 0;
    final itemTotal = (summary['itemTotal'] as num?)?.toDouble() ?? 0;
    final gstSubtotal = (summary['gstSubtotal'] as num?)?.toDouble() ?? 0;
    final grandTotal = (summary['grandTotal'] as num?)?.toDouble() ?? 0;
    final totalSaved = (summary['totalSavedAmount'] as num?)?.toDouble() ?? 0;
    final gstByHsn = (invoice['gstByHsn'] as List? ?? const []).map((item) => Map<String, dynamic>.from(item as Map)).toList();
    String amount(dynamic value) => 'Rs.${((value as num?)?.toDouble() ?? 0).toStringAsFixed(2)}';

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(header['companyName']?.toString() ?? '', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                for (final value in (header['addresses'] as List? ?? const [])) pw.Text(value.toString()),
                for (final value in (header['mobileNumbers'] as List? ?? const [])) pw.Text(value.toString()),
                pw.Text('Customer Care: ${header['customerCareMobile'] ?? ''}'),
                pw.Text(header['customerCareEmail']?.toString() ?? ''),
              ]),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: 'INVOICE:$invoiceId', width: 72, height: 72),
                pw.SizedBox(height: 4),
                pw.Text('Invoice Date: ${invoice['invoiceDate'] ?? ''}'),
              ]),
            ]),
            pw.SizedBox(height: 16),
            pw.Divider(),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Billing / Shipping Address', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 4),
                      pw.Text(address?.name.isNotEmpty == true ? address!.name : widget.order.customerName),
                      if (address != null) pw.Text(address.addressLine),
                      if (address != null) pw.Text('${address.city}, ${address.district}, ${address.state} - ${address.pincode}'),
                      pw.Text('Mobile: ${address?.mobileNumber ?? widget.order.customerMobile ?? '-'}'),
                      if ((widget.order.customerEmail ?? address?.email ?? '').isNotEmpty) pw.Text('Email: ${widget.order.customerEmail ?? address?.email}'),
                    ],
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Invoice ID: $invoiceId'),
                      pw.Text('Order Number: ${widget.order.orderNumber.isNotEmpty ? widget.order.orderNumber : widget.order.id}'),
                      pw.Text('Order Date: ${invoice['invoiceDate'] ?? widget.order.createdAt}'),
                      pw.Text('Payment Method: ${widget.order.paymentMethod}'),
                      pw.Text('Payment Status: ${widget.order.paymentStatus}'),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400),
              columnWidths: {
                0: const pw.FlexColumnWidth(0.5),
                1: const pw.FlexColumnWidth(1.1),
                2: const pw.FlexColumnWidth(2.6),
                3: const pw.FlexColumnWidth(1),
                4: const pw.FlexColumnWidth(0.8),
                5: const pw.FlexColumnWidth(1.1),
                6: const pw.FlexColumnWidth(1.1),
                7: const pw.FlexColumnWidth(0.9),
                8: const pw.FlexColumnWidth(0.9),
                9: const pw.FlexColumnWidth(1.2),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _cell('Sl No', bold: true), _cell('SKU', bold: true), _cell('Item Details', bold: true),
                    _cell('HSN Code', bold: true), _cell('Unit', bold: true), _cell('MRP', bold: true),
                    _cell('Rate', bold: true), _cell('GST Rate', bold: true), _cell('Disc', bold: true), _cell('Total', bold: true),
                  ],
                ),
                for (final item in invoiceItems)
                  pw.TableRow(children: [
                    _cell('${item['slNo']}'), _cell(item['sku']?.toString() ?? ''), _cell(item['itemDetails']?.toString() ?? ''),
                    _cell(item['hsnCode']?.toString() ?? ''), _cell('${item['unit'] ?? item['quantity']}'),
                    _cell(amount(item['mrp'])), _cell(amount(item['rate'])), _cell('${item['gstRate'] ?? 0}%'),
                    _cell(amount(item['discount'])), _cell(amount(item['total'])),
                  ]),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Subtotal: ${amount(subtotal)}'),
                  pw.Text('Item Total: ${amount(itemTotal)}'),
                  pw.Text('GST Subtotal: ${amount(gstSubtotal)}'),
                  pw.SizedBox(height: 6),
                  pw.Text('SECTION-1 - GST SUBTOTAL BY HSN CODE', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                  for (final group in gstByHsn) pw.Text('HSN ${group['hsnCode']}: Taxable ${amount(group['taxableAmount'])} | GST ${group['gstRate']}% ${amount(group['gstAmount'])}', style: const pw.TextStyle(fontSize: 10)),
                  pw.SizedBox(height: 4),
                  pw.Text('GRAND TOTAL: ${amount(grandTotal)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
                  pw.Text('TOTAL SAVED: ${amount(totalSaved)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                ],
              ),
            ),
            pw.SizedBox(height: 14),
            pw.Container(padding: const pw.EdgeInsets.all(10), decoration: pw.BoxDecoration(color: PdfColors.green50, border: pw.Border.all(color: PdfColors.green700), borderRadius: pw.BorderRadius.circular(6)), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Center(child: pw.Text('YOUR REFERRAL EARNINGS', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13))),
              pw.SizedBox(height: 6),
              pw.Text('Total Referral Commission Earned: ${amount(referral['totalCommissionEarned'])}'),
              pw.Text('Total Referral Payout: ${amount(referral['totalPayout'])}'),
              pw.Text('Wallet Balance: ${amount(referral['walletBalance'])}'),
            ])),
            pw.Spacer(),
            pw.Divider(),
            pw.Center(child: pw.Text('Thank you for shopping with VioLeafy!', style: const pw.TextStyle(fontSize: 10))),
          ],
        ),
      ),
    );

    final bytes = await doc.save();
    _cachedPdfBytes = bytes;
    return bytes;
  }

  static pw.Widget _cell(String text, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text(text, style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, fontSize: 10)),
      );

  Widget _invoiceDetails() {
    final summary = Map<String, dynamic>.from(_invoiceData['summary'] as Map? ?? const {});
    final referral = Map<String, dynamic>.from(_invoiceData['referralSummary'] as Map? ?? const {});
    final header = Map<String, dynamic>.from(_invoiceData['header'] as Map? ?? const {});
    String money(dynamic value) => 'Rs.${((value as num?)?.toDouble() ?? 0).toStringAsFixed(2)}';
    Widget valueRow(String label, dynamic value, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(fontWeight: strong ? FontWeight.bold : FontWeight.normal)),
        Text(money(value), style: TextStyle(fontWeight: strong ? FontWeight.bold : FontWeight.normal, fontSize: strong ? 16 : 14)),
      ]),
    );

    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(header['companyName']?.toString() ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              for (final address in (header['addresses'] as List? ?? const [])) Text(address.toString()),
              for (final mobile in (header['mobileNumbers'] as List? ?? const [])) Text(mobile.toString()),
              Text('Customer Care: ${header['customerCareMobile'] ?? ''}'),
              Text(header['customerCareEmail']?.toString() ?? ''),
              const Divider(),
              Text('Invoice ID: ${_invoiceData['invoiceId'] ?? widget.order.id}', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('Invoice Date: ${_invoiceData['invoiceDate'] ?? ''}'),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Sl No')), DataColumn(label: Text('SKU')), DataColumn(label: Text('Item Details')),
                DataColumn(label: Text('HSN Code')), DataColumn(label: Text('Unit')), DataColumn(label: Text('MRP')),
                DataColumn(label: Text('Rate')), DataColumn(label: Text('GST Rate')), DataColumn(label: Text('Disc')), DataColumn(label: Text('Total')),
              ],
              rows: _invoiceItems.map((item) => DataRow(cells: [
                DataCell(Text('${item['slNo']}')), DataCell(Text(item['sku']?.toString() ?? '')), DataCell(Text(item['itemDetails']?.toString() ?? '')),
                DataCell(Text(item['hsnCode']?.toString() ?? '')), DataCell(Text('${item['unit'] ?? item['quantity']}')), DataCell(Text(money(item['mrp']))),
                DataCell(Text(money(item['rate']))), DataCell(Text('${item['gstRate'] ?? 0}%')), DataCell(Text(money(item['discount']))), DataCell(Text(money(item['total']))),
              ])).toList(),
            ),
          ),
        ),
      ),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        valueRow('Subtotal', summary['subtotal']), valueRow('Item Total', summary['itemTotal']), valueRow('GST Subtotal', summary['gstSubtotal']),
        const Divider(), valueRow('GRAND TOTAL', summary['grandTotal'], strong: true), valueRow('TOTAL SAVED', summary['totalSavedAmount'], strong: true),
      ]))),
      Card(color: AppColors.primaryGreen.withValues(alpha: 0.1), child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        const Text('YOUR REFERRAL EARNINGS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        valueRow('Commission Earned', referral['totalCommissionEarned']), valueRow('Payout', referral['totalPayout']), valueRow('Wallet Balance', referral['walletBalance']),
      ]))),
    ]);
  }

  Future<void> _sharePdf(BuildContext context) async {
    try {
      final bytes = _cachedPdfBytes ?? await _buildPdf();
      await Printing.sharePdf(bytes: bytes, filename: _fileName);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to share invoice: $e')),
        );
      }
    }
  }

  Future<void> _printPdf(BuildContext context) async {
    try {
      final bytes = _cachedPdfBytes ?? await _buildPdf();
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => bytes,
        name: _fileName,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to print invoice: $e')),
        );
      }
    }
  }

  Future<void> _download(BuildContext context) async {
    try {
      final bytes = _cachedPdfBytes ?? await _buildPdf();
      await downloadPdfFile(bytes, _fileName);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invoice download started.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to download invoice: $e')),
        );
      }
    }
  }

  void _retry() {
    setState(() {
      _cachedPdfBytes = null;
      _pdfFuture = _buildPdf();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.secondaryBackground,
      appBar: AppBar(
        title: const Text('Invoice', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share',
            onPressed: () => _sharePdf(context),
          ),
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Print',
            onPressed: () => _printPdf(context),
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Download',
            onPressed: () => _download(context),
          ),
        ],
      ),
      body: FutureBuilder<Uint8List>(
        future: _pdfFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
          }

          if (snapshot.hasError || !snapshot.hasData) {
            final errorMsg = snapshot.error?.toString() ?? 'Invoice generation failed';
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 52, color: AppColors.error),
                    const SizedBox(height: 12),
                    const Text('Unable to display the document.', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text(
                      errorMsg.contains('404')
                          ? 'Invoice details are currently processing. Please try again in a moment.'
                          : 'The invoice could not be generated. Please try again or download it.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      alignment: WrapAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _retry,
                          icon: const Icon(Icons.refresh_outlined),
                          label: const Text('Try Again'),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _download(context),
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('Download Invoice'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }

          return Column(
            children: [
              Expanded(
                child: _invoiceDetails(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _invoiceItems.any((item) => item['productId'].toString().isNotEmpty)
                          ? () {
                              ref.read(shoppingRepositoryProvider).addInvoiceItemsToCart(_invoiceItems);
                              context.push('/cart');
                            }
                          : null,
                      icon: const Icon(Icons.replay_outlined),
                      label: const Text('Buy Again'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => context.push('/referrals'),
                      icon: const Icon(Icons.group_add_outlined),
                      label: const Text('Invite Friends & Earn'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => context.push('/wallet'),
                      icon: const Icon(Icons.account_balance_wallet_outlined),
                      label: const Text('View Wallet'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => context.go('/'),
                      icon: const Icon(Icons.shopping_bag_outlined),
                      label: const Text('Continue Shopping'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
