import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/file_download_helper.dart';
import '../../../models/models.dart';
import '../../../providers/app_providers.dart';

/// Tax Invoice & Pre-Order Advance Receipt preview with share/print/download actions.
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
  List<Map<String, dynamic>> _preorderItems = const [];
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
    final preorderItems = (invoice['preorderItems'] as List? ?? const []).map((item) => Map<String, dynamic>.from(item as Map)).toList();
    _invoiceItems = invoiceItems;
    _preorderItems = preorderItems;
    final doc = pw.Document();
    final address = widget.order.shippingAddress;
    final invoiceId = invoice['invoiceId']?.toString() ?? widget.order.id;
    final documentType = invoice['documentType']?.toString() ?? (invoiceItems.isEmpty && preorderItems.isNotEmpty ? 'PREORDER_RECEIPT' : 'TAX_INVOICE');

    final regularSalesSubtotal = (summary['regularSalesSubtotal'] ?? summary['itemTotal'] ?? summary['subtotal'] ?? 0 as num).toDouble();
    final regularSalesGst = (summary['regularSalesGst'] ?? summary['gstSubtotal'] ?? 0 as num).toDouble();
    final regularInvoiceGrandTotal = (summary['regularInvoiceGrandTotal'] ?? summary['grandTotal'] ?? 0 as num).toDouble();
    final preorderBookingAdvance = (summary['preorderBookingAdvance'] ?? 0 as num).toDouble();
    final customerGrandTotalPayable = (summary['customerGrandTotalPayable'] ?? (regularInvoiceGrandTotal + preorderBookingAdvance)).toDouble();
    final totalSaved = (summary['totalSavedAmount'] as num?)?.toDouble() ?? 0;
    final gstByHsn = (invoice['gstByHsn'] as List? ?? const []).map((item) => Map<String, dynamic>.from(item as Map)).toList();
    String amount(dynamic value) => 'Rs.${((value as num?)?.toDouble() ?? 0).toStringAsFixed(2)}';

    pw.Widget logoWidget;
    try {
      final logoUrl = header['companyLogo']?.toString() ?? '';
      if (logoUrl.isNotEmpty) {
        final logoResp = await http.get(Uri.parse(logoUrl)).timeout(const Duration(seconds: 4));
        if (logoResp.statusCode == 200) {
          final logoImage = pw.MemoryImage(logoResp.bodyBytes);
          logoWidget = pw.Image(logoImage, height: 45);
        } else {
          logoWidget = pw.Text(header['companyName']?.toString() ?? 'VAMJO', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold));
        }
      } else {
        logoWidget = pw.Text(header['companyName']?.toString() ?? 'VAMJO', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold));
      }
    } catch (_) {
      logoWidget = pw.Text(header['companyName']?.toString() ?? 'VAMJO', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold));
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              logoWidget,
              pw.SizedBox(height: 4),
              if ((header['addressess']?.toString() ?? '').isNotEmpty) pw.Text(header['addressess'].toString(), style: const pw.TextStyle(fontSize: 9)),
              if ((header['addressess1']?.toString() ?? '').isNotEmpty) pw.Text(header['addressess1'].toString(), style: const pw.TextStyle(fontSize: 9)),
              if ((header['addressess']?.toString() ?? '').isEmpty && (header['addresses'] as List? ?? const []).isNotEmpty)
                for (final value in (header['addresses'] as List? ?? const [])) pw.Text(value.toString(), style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 2),
              pw.Text(
                '${header['customerCareEmail'] ?? 'sales@vamjo.com'} , Customer care : ${header['customerCareNumber'] ?? header['customerCareMobile'] ?? ''}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.SizedBox(height: 2),
              if ((header['gstNo']?.toString() ?? header['gstno']?.toString() ?? '').isNotEmpty)
                pw.Text('GSTIN: ${header['gstNo'] ?? header['gstno']}', style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 2),
              if ((header['webAddress']?.toString() ?? '').isNotEmpty)
                pw.Text(header['webAddress'].toString(), style: const pw.TextStyle(fontSize: 9)),
            ]),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text(
                documentType == 'PREORDER_RECEIPT' ? 'PRE-ORDER ADVANCE RECEIPT' : 'TAX INVOICE',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 4),
              pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: 'INVOICE:$invoiceId', width: 64, height: 64),
              pw.SizedBox(height: 4),
              pw.Text('Invoice Date: ${invoice['invoiceDate'] ?? ''}'),
            ]),
          ]),
          pw.SizedBox(height: 12),
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
          pw.SizedBox(height: 16),

          // Section 6.1: Normal Sales Items First
          if (invoiceItems.isNotEmpty) ...[
            pw.Text('REGULAR SALES ITEMS', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
            pw.SizedBox(height: 6),
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
            pw.SizedBox(height: 14),
          ],

          // Section 6.2: Pre-Order Booking Section (Immediately Below Normal Sales Items)
          if (preorderItems.isNotEmpty) ...[
            pw.Text('PRE-ORDER BOOKING ITEMS', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400),
              columnWidths: const {
                0: pw.FlexColumnWidth(1.8),
                1: pw.FlexColumnWidth(0.6),
                2: pw.FlexColumnWidth(1.0),
                3: pw.FlexColumnWidth(1.1),
                4: pw.FlexColumnWidth(1.2),
                5: pw.FlexColumnWidth(1.1),
                6: pw.FlexColumnWidth(1.1),
                7: pw.FlexColumnWidth(2.2),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _cell('Product Name', bold: true),
                    _cell('Qty', bold: true),
                    _cell('Online Price', bold: true),
                    _cell('Total Value', bold: true),
                    _cell('Payment Type', bold: true),
                    _cell('Booking Advance', bold: true),
                    _cell('Remaining Bal', bold: true),
                    _cell('Booking Details', bold: true),
                  ],
                ),
                for (final po in preorderItems)
                  pw.TableRow(children: [
                    _cell(po['productName']?.toString() ?? ''),
                    _cell('${po['quantity'] ?? 1}'),
                    _cell(amount(po['onlinePrice'])),
                    _cell(amount(po['totalProductValue'])),
                    _cell(po['paymentTypeLabel']?.toString() ?? po['paymentType']?.toString() ?? ''),
                    _cell(amount(po['bookingAdvance'])),
                    _cell(amount(po['remainingBalance'])),
                    _cell(
                      'Ref: ${po['preorderId'] ?? "-"}\n'
                      'Delivery: ${po['expectedDeliveryDate'] ?? "-"}\n'
                      'Courier: ${po['preferredCourierAgent'] ?? "-"}\n'
                      'Gift Wrap: ${(po['giftWrap'] == true || po['giftWrap'] == "Yes") ? "Yes" : "No"}\n'
                      'Suggestion: ${(po['specialSuggestion']?.toString().isNotEmpty == true) ? po['specialSuggestion'] : "None"}',
                    ),
                  ]),
              ],
            ),
            pw.SizedBox(height: 14),
          ],

          // Section 6.3: Invoice Totals Section in Exact Required Order
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Regular Sales Subtotal: ${amount(regularSalesSubtotal)}'),
                pw.Text('GST on Regular Sales: ${amount(regularSalesGst)}'),
                pw.Text('REGULAR INVOICE GRAND TOTAL: ${amount(regularInvoiceGrandTotal)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                pw.Text('Pre-Order Booking Advance: ${amount(preorderBookingAdvance)}'),
                pw.SizedBox(height: 4),
                pw.Text('CUSTOMER GRAND TOTAL PAYABLE: ${amount(customerGrandTotalPayable)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 15)),
                if (totalSaved > 0)
                  pw.Text('TOTAL SAVED: ${amount(totalSaved)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                if (gstByHsn.isNotEmpty) ...[
                  pw.SizedBox(height: 8),
                  pw.Text('GST BREAKDOWN BY HSN CODE & RATE (REGULAR SALES)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                  pw.SizedBox(height: 4),
                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey400),
                    columnWidths: const {
                      0: pw.FlexColumnWidth(1.2),
                      1: pw.FlexColumnWidth(1.0),
                      2: pw.FlexColumnWidth(1.5),
                      3: pw.FlexColumnWidth(1.5),
                      4: pw.FlexColumnWidth(1.5),
                    },
                    children: [
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                        children: [
                          _cell('HSN Code', bold: true),
                          _cell('GST Rate', bold: true),
                          _cell('Taxable Value', bold: true),
                          _cell('GST Amount', bold: true),
                          _cell('Total', bold: true),
                        ],
                      ),
                      for (final group in gstByHsn)
                        pw.TableRow(
                          children: [
                            _cell(group['hsnCode']?.toString() ?? '-'),
                            _cell('${group['gstRate'] ?? 0}%'),
                            _cell(amount(group['taxableAmount'])),
                            _cell(amount(group['gstAmount'])),
                            _cell(amount(((group['taxableAmount'] as num?)?.toDouble() ?? 0) + ((group['gstAmount'] as num?)?.toDouble() ?? 0))),
                          ],
                        ),
                    ],
                  ),
                ],
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
          pw.SizedBox(height: 16),
          pw.Divider(),
          pw.Center(child: pw.Text('Thank you for shopping with VioLeafy!', style: const pw.TextStyle(fontSize: 10))),
        ],
      ),
    );

    final bytes = await doc.save();
    _cachedPdfBytes = bytes;
    return bytes;
  }

  static pw.Widget _cell(String text, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text(text, style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, fontSize: 9)),
      );

  Widget _invoiceDetails() {
    final summary = Map<String, dynamic>.from(_invoiceData['summary'] as Map? ?? const {});
    final referral = Map<String, dynamic>.from(_invoiceData['referralSummary'] as Map? ?? const {});
    final header = Map<String, dynamic>.from(_invoiceData['header'] as Map? ?? const {});
    final documentType = _invoiceData['documentType']?.toString() ?? (_invoiceItems.isEmpty && _preorderItems.isNotEmpty ? 'PREORDER_RECEIPT' : 'TAX_INVOICE');

    final regularSalesSubtotal = (summary['regularSalesSubtotal'] ?? summary['itemTotal'] ?? summary['subtotal'] ?? 0 as num).toDouble();
    final regularSalesGst = (summary['regularSalesGst'] ?? summary['gstSubtotal'] ?? 0 as num).toDouble();
    final regularInvoiceGrandTotal = (summary['regularInvoiceGrandTotal'] ?? summary['grandTotal'] ?? 0 as num).toDouble();
    final preorderBookingAdvance = (summary['preorderBookingAdvance'] ?? 0 as num).toDouble();
    final customerGrandTotalPayable = (summary['customerGrandTotalPayable'] ?? (regularInvoiceGrandTotal + preorderBookingAdvance)).toDouble();

    String money(dynamic value) => 'Rs.${((value as num?)?.toDouble() ?? 0).toStringAsFixed(2)}';
    Widget valueRow(String label, dynamic value, {bool strong = false, Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: strong ? FontWeight.bold : FontWeight.normal,
              color: color,
            ),
          ),
        ),
        Text(
          money(value),
          style: TextStyle(
            fontWeight: strong ? FontWeight.bold : FontWeight.normal,
            fontSize: strong ? 15 : 14,
            color: color,
          ),
        ),
      ]),
    );

    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: (header['companyLogo']?.toString() ?? '').isNotEmpty
                        ? Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Image.network(
                              header['companyLogo'].toString(),
                              height: 50,
                              fit: BoxFit.contain,
                              alignment: Alignment.centerLeft,
                              errorBuilder: (context, error, stackTrace) => Text(
                                header['companyName']?.toString() ?? 'VAMJO',
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                              ),
                            ),
                          )
                        : Text(
                            header['companyName']?.toString() ?? 'VAMJO',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      documentType == 'PREORDER_RECEIPT' ? 'PRE-ORDER ADVANCE RECEIPT' : 'TAX INVOICE',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if ((header['addressess']?.toString() ?? '').isNotEmpty)
                Text(header['addressess'].toString(), style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              if ((header['addressess1']?.toString() ?? '').isNotEmpty)
                Text(header['addressess1'].toString(), style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              if ((header['addressess']?.toString() ?? '').isEmpty && (header['addresses'] as List? ?? const []).isNotEmpty)
                for (final address in (header['addresses'] as List? ?? const []))
                  Text(address.toString(), style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 2),
              Text(
                '${header['customerCareEmail'] ?? 'sales@vamjo.com'} , Customer care : ${header['customerCareNumber'] ?? header['customerCareMobile'] ?? ''}',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 2),
              if ((header['gstNo']?.toString() ?? header['gstno']?.toString() ?? '').isNotEmpty)
                Text(
                  'GSTIN: ${header['gstNo'] ?? header['gstno']}',
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                ),
              const SizedBox(height: 2),
              if ((header['webAddress']?.toString() ?? '').isNotEmpty)
                Text(
                  header['webAddress'].toString(),
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              const Divider(height: 24),
              Text('Invoice ID: ${_invoiceData['invoiceId'] ?? widget.order.id}', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('Invoice Date: ${_invoiceData['invoiceDate'] ?? ''}'),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),

      // Section 6.1: Normal Sales Items First
      if (_invoiceItems.isNotEmpty) ...[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'REGULAR SALES ITEMS',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
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
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],

      // Section 6.2: Pre-Order Booking Items Section Immediately Below Normal Sales Items
      if (_preorderItems.isNotEmpty) ...[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PRE-ORDER BOOKING ITEMS',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primaryGreen),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Advance bookings excluded from regular sales GST calculations',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Product Name')),
                      DataColumn(label: Text('Quantity')),
                      DataColumn(label: Text('Online Price')),
                      DataColumn(label: Text('Total Product Value')),
                      DataColumn(label: Text('Payment Type')),
                      DataColumn(label: Text('Booking Advance')),
                      DataColumn(label: Text('Remaining Balance')),
                      DataColumn(label: Text('Gift Wrap')),
                      DataColumn(label: Text('Special Suggestion')),
                      DataColumn(label: Text('Expected Date of Delivery')),
                      DataColumn(label: Text('Preferred Courier Agent')),
                      DataColumn(label: Text('Pre-Order Booking Reference')),
                    ],
                    rows: _preorderItems.map((po) {
                      final giftWrap = (po['giftWrap'] == true || po['giftWrap'] == 'Yes') ? 'Yes' : 'No';
                      final suggestion = (po['specialSuggestion']?.toString().trim().isNotEmpty == true)
                          ? po['specialSuggestion'].toString()
                          : 'None';
                      return DataRow(cells: [
                        DataCell(Text(po['productName']?.toString() ?? '')),
                        DataCell(Text('${po['quantity'] ?? 1}')),
                        DataCell(Text(money(po['onlinePrice']))),
                        DataCell(Text(money(po['totalProductValue']))),
                        DataCell(Text(po['paymentTypeLabel']?.toString() ?? po['paymentType']?.toString() ?? '')),
                        DataCell(Text(money(po['bookingAdvance']), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryGreen))),
                        DataCell(Text(money(po['remainingBalance']))),
                        DataCell(Text(giftWrap)),
                        DataCell(Text(suggestion)),
                        DataCell(Text(po['expectedDeliveryDate']?.toString() ?? '-')),
                        DataCell(Text(po['preferredCourierAgent']?.toString() ?? '-')),
                        DataCell(Text(po['preorderId']?.toString() ?? '-')),
                      ]);
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],

      // Section 6.3: Invoice Totals Section in Exact Required Order
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              valueRow('Regular Sales Subtotal', regularSalesSubtotal),
              valueRow('GST on Regular Sales', regularSalesGst),
              const Divider(),
              valueRow('REGULAR INVOICE GRAND TOTAL', regularInvoiceGrandTotal, strong: true),
              valueRow('Pre-Order Booking Advance', preorderBookingAdvance, color: AppColors.primaryGreen),
              const Divider(),
              valueRow('CUSTOMER GRAND TOTAL PAYABLE', customerGrandTotalPayable, strong: true, color: AppColors.primaryGreen),
              if (((summary['totalSavedAmount'] as num?)?.toDouble() ?? 0) > 0)
                valueRow('TOTAL SAVED', summary['totalSavedAmount'], strong: true),
            ],
          ),
        ),
      ),

      if ((_invoiceData['gstByHsn'] as List? ?? []).isNotEmpty) ...[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('HSN-Wise GST Breakdown (Regular Sales)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('HSN Code', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('GST Rate', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Taxable Value', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('GST Amount', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Total', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                    rows: (_invoiceData['gstByHsn'] as List? ?? []).map((group) {
                      final itemMap = Map<String, dynamic>.from(group as Map);
                      final taxVal = (itemMap['taxableAmount'] as num?)?.toDouble() ?? 0.0;
                      final gstVal = (itemMap['gstAmount'] as num?)?.toDouble() ?? 0.0;
                      return DataRow(cells: [
                        DataCell(Text(itemMap['hsnCode']?.toString() ?? '-')),
                        DataCell(Text('${itemMap['gstRate'] ?? 0}%')),
                        DataCell(Text(money(taxVal))),
                        DataCell(Text(money(gstVal))),
                        DataCell(Text(money(taxVal + gstVal), style: const TextStyle(fontWeight: FontWeight.bold))),
                      ]);
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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
