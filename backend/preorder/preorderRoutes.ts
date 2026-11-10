/**
 * LeafyEarth Pre-Order Booking Module — Express Route Handlers (`/api/v1/preorders/...`).
 *
 * Standard error envelope: `{ code, message, requestId }`
 */

import crypto from 'crypto';
import type { Express, Request, Response } from 'express';
import { createPreorderService } from './preorderService';
import {
  DEFAULT_PREORDER_CONFIG,
  type PreorderBookingStatus,
  type PreorderConfig,
  PreorderDomainError,
  type PreorderErrorCode,
} from './preorderTypes';

export interface PreorderRouteDeps {
  adminDb: any;
  getAuthenticatedUser: (req: any) => Promise<any>;
  findCustomerByAuthUser?: (user: any) => Promise<any | null>;
  config?: PreorderConfig;
  now?: () => Date;
}

const rateBuckets = new Map<string, number[]>();
function isRateLimited(key: string, maxRequests: number, windowMs: number): boolean {
  const now = Date.now();
  const recent = (rateBuckets.get(key) || []).filter((t) => now - t < windowMs);
  if (recent.length >= maxRequests) {
    rateBuckets.set(key, recent);
    return true;
  }
  recent.push(now);
  rateBuckets.set(key, recent);
  return false;
}

function makeRequestId(req: Request): string {
  const hdr = req.headers?.['x-request-id'];
  if (typeof hdr === 'string' && /^[A-Za-z0-9_\-]{6,64}$/.test(hdr)) {
    return hdr;
  }
  return `req_${crypto.randomBytes(8).toString('hex')}`;
}

function sendError(
  res: Response,
  requestId: string,
  code: PreorderErrorCode,
  message: string,
  httpStatus: number
) {
  return res.status(httpStatus).json({
    code,
    message,
    error: message, // backward-compatible alias for existing ApiClient error extractor
    requestId,
  });
}

function assertAllowedKeys(body: unknown, allowedKeys: readonly string[]): void {
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    throw new PreorderDomainError('VALIDATION_ERROR', 'Request body must be a JSON object.', 400);
  }
  const unknown = Object.keys(body as Record<string, unknown>).filter(
    (k) => !allowedKeys.includes(k)
  );
  if (unknown.length > 0) {
    throw new PreorderDomainError(
      'VALIDATION_ERROR',
      `Unknown request field(s): ${unknown.join(', ')}`,
      400
    );
  }
}

export function registerPreorderRoutes(app: Express, deps: PreorderRouteDeps) {
  const { adminDb, getAuthenticatedUser, findCustomerByAuthUser } = deps;
  const service = createPreorderService({
    adminDb,
    config: deps.config || DEFAULT_PREORDER_CONFIG,
    now: deps.now,
  });

  const isAnonOrMissing = (user: any): boolean =>
    !user ||
    !user.uid ||
    user.firebase?.sign_in_provider === 'anonymous' ||
    user.provider_id === 'anonymous';

  async function requireAuthUser(
    req: Request,
    res: Response,
    requestId: string
  ): Promise<any | null> {
    const user = await getAuthenticatedUser(req);
    if (isAnonOrMissing(user)) {
      sendError(
        res,
        requestId,
        'UNAUTHENTICATED',
        'Authentication is required for pre-order operations.',
        401
      );
      return null;
    }
    return user;
  }

  async function checkIsAdmin(user: any): Promise<boolean> {
    if (!user?.uid) return false;
    if (user.admin === true) return true;
    try {
      const userSnap = await adminDb.collection('users').doc(String(user.uid)).get();
      return Boolean(userSnap.exists && userSnap.data()?.role === 'Admin');
    } catch (_) {
      return false;
    }
  }

  function handleRouteError(
    res: Response,
    requestId: string,
    err: unknown,
    contextLabel: string
  ) {
    if (err instanceof PreorderDomainError) {
      return sendError(res, requestId, err.code, err.message, err.httpStatus);
    }
    console.error(
      `[Preorder API] ${contextLabel} error (${requestId}):`,
      (err as any)?.message || err
    );
    return sendError(res, requestId, 'INTERNAL_ERROR', 'An unexpected server error occurred.', 500);
  }

  // 1. GET /api/v1/preorders/eligible-products
  app.get('/api/v1/preorders/eligible-products', async (req: Request, res: Response) => {
    const requestId = makeRequestId(req);
    try {
      const clientKey = req.ip || 'anon';
      if (isRateLimited(`elig:${clientKey}`, 120, 60_000)) {
        return sendError(
          res,
          requestId,
          'RATE_LIMITED',
          'Too many requests. Please try again shortly.',
          429
        );
      }
      const limit = req.query.limit ? Number(req.query.limit) : undefined;
      const cursor = typeof req.query.cursor === 'string' ? req.query.cursor : undefined;
      const result = await service.listEligibleProducts({ limit, cursor });
      return res.status(200).json({ ...result, requestId });
    } catch (err) {
      return handleRouteError(res, requestId, err, 'listEligibleProducts');
    }
  });

  // 2. GET /api/v1/preorders/couriers
  app.get('/api/v1/preorders/couriers', async (req: Request, res: Response) => {
    const requestId = makeRequestId(req);
    try {
      const result = await service.listCourierAgents();
      return res.status(200).json({ ...result, requestId });
    } catch (err) {
      return handleRouteError(res, requestId, err, 'listCourierAgents');
    }
  });

  // 3. POST /api/v1/preorders
  app.post('/api/v1/preorders', async (req: Request, res: Response) => {
    const requestId = makeRequestId(req);
    try {
      const user = await requireAuthUser(req, res, requestId);
      if (!user) return;
      if (isRateLimited(`create:${user.uid}`, 30, 60_000)) {
        return sendError(
          res,
          requestId,
          'RATE_LIMITED',
          'Too many booking attempts. Please wait a moment.',
          429
        );
      }

      assertAllowedKeys(req.body, [
        'productId',
        'quantity',
        'paymentType',
        'bookingAdvance',
        'giftWrap',
        'specialSuggestion',
        'expectedDeliveryDate',
        'preferredCourierAgent',
        'idempotencyKey',
      ]);

      let customer: any = null;
      if (findCustomerByAuthUser) {
        try {
          customer = await findCustomerByAuthUser(user);
        } catch (_) {}
      }

      const displayName = String(customer?.name || user.name || 'LeafyEarth Customer').trim();
      const result = await service.createPreorder({
        userId: String(user.uid),
        customerId: String(customer?.id || user.uid),
        customerDisplayName: displayName,
        productId: String(req.body.productId || ''),
        quantity: Number(req.body.quantity),
        paymentType: req.body.paymentType,
        bookingAdvance: req.body.bookingAdvance,
        giftWrap: req.body.giftWrap,
        specialSuggestion: req.body.specialSuggestion,
        expectedDeliveryDate: req.body.expectedDeliveryDate,
        preferredCourierAgent: req.body.preferredCourierAgent,
        idempotencyKey: String(req.body.idempotencyKey || ''),
      });

      return res.status(result.idempotentReplay ? 200 : 201).json({
        preorder: result.booking,
        idempotentReplay: result.idempotentReplay,
        requestId,
      });
    } catch (err) {
      return handleRouteError(res, requestId, err, 'createPreorder');
    }
  });

  // 4. GET /api/v1/preorders/mine
  app.get('/api/v1/preorders/mine', async (req: Request, res: Response) => {
    const requestId = makeRequestId(req);
    try {
      const user = await requireAuthUser(req, res, requestId);
      if (!user) return;
      const limit = req.query.limit ? Number(req.query.limit) : undefined;
      const cursor = typeof req.query.cursor === 'string' ? req.query.cursor : undefined;
      const result = await service.listMyPreorders({
        userId: String(user.uid),
        limit,
        cursor,
      });
      return res.status(200).json({ ...result, requestId });
    } catch (err) {
      return handleRouteError(res, requestId, err, 'listMyPreorders');
    }
  });

  // 5. GET /api/v1/preorders/:id
  app.get('/api/v1/preorders/:id', async (req: Request, res: Response) => {
    const requestId = makeRequestId(req);
    try {
      const user = await requireAuthUser(req, res, requestId);
      if (!user) return;
      const isAdmin = await checkIsAdmin(user);
      const preorder = await service.getPreorderById({
        preorderId: String(req.params.id || ''),
        requesterUid: String(user.uid),
        isAdmin,
      });
      return res.status(200).json({ preorder, requestId });
    } catch (err) {
      return handleRouteError(res, requestId, err, 'getPreorderById');
    }
  });

  // 6. POST /api/v1/preorders/:id/cancel
  app.post('/api/v1/preorders/:id/cancel', async (req: Request, res: Response) => {
    const requestId = makeRequestId(req);
    try {
      const user = await requireAuthUser(req, res, requestId);
      if (!user) return;
      if (req.body && Object.keys(req.body).length > 0) {
        assertAllowedKeys(req.body, ['reason']);
      }
      const isAdmin = await checkIsAdmin(user);
      const preorder = await service.cancelPreorder({
        preorderId: String(req.params.id || ''),
        requesterUid: String(user.uid),
        isAdmin,
        reason: req.body?.reason ? String(req.body.reason) : undefined,
      });
      return res.status(200).json({ preorder, requestId });
    } catch (err) {
      return handleRouteError(res, requestId, err, 'cancelPreorder');
    }
  });

  // 7. PATCH /api/v1/admin/preorders/:id/status (also supports POST for clients without PATCH)
  const adminStatusHandler = async (req: Request, res: Response) => {
    const requestId = makeRequestId(req);
    try {
      const user = await requireAuthUser(req, res, requestId);
      if (!user) return;
      const isAdmin = await checkIsAdmin(user);
      if (!isAdmin) {
        return sendError(res, requestId, 'FORBIDDEN', 'Administrator role is required.', 403);
      }

      assertAllowedKeys(req.body, ['status', 'bookingStatus', 'note']);
      const targetStatus = String(req.body.bookingStatus || req.body.status || '') as PreorderBookingStatus;
      const preorder = await service.adminUpdateStatus({
        preorderId: String(req.params.id || ''),
        adminUid: String(user.uid),
        nextStatus: targetStatus,
        note: req.body.note ? String(req.body.note) : undefined,
      });
      return res.status(200).json({ preorder, requestId });
    } catch (err) {
      return handleRouteError(res, requestId, err, 'adminUpdateStatus');
    }
  };

  app.patch('/api/v1/admin/preorders/:id/status', adminStatusHandler);
  app.post('/api/v1/admin/preorders/:id/status', adminStatusHandler);

  return service;
}
