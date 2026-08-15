# Remove Mock Data & Hardcoded Initializers

This plan outlines the steps to remove hardcoded arrays, mock data, and in-memory initializers from the Violeafy application to ensure it relies exclusively on the `violeafydb` database.

## User Review Required

> [!IMPORTANT]
> The `Explore Categories` screen will now be dynamic. If the database is empty, it will show an empty state instead of the previous hardcoded categories.
> The `Trending Searches` section in the search screen will be removed as it was based on a hardcoded list.

## Proposed Changes

### Backend (`server.ts`)

#### [MODIFY] [server.ts](file:///D:/violeafycrossapp/server.ts)
- Remove the hardcoded fallback categories `["Fruits", "Vegetables", "Spices", "Flowers"]` from the `/api/categories` endpoint.
- Comment out the `dummy...` data arrays (`dummyProducts`, `dummyCoupons`, `dummyLevels`, `dummyUsers`, `dummyReferrals`, `dummyWallets`, `dummyDeliveries`).
- Comment out the population logic inside the `/api/database/populate` endpoint.

### Flutter App (`lib/`)

#### [MODIFY] [categories_screen.dart](file:///D:/violeafycrossapp/lib/features/products/presentation/categories_screen.dart)
- Comment out/Remove the `_categoryData` hardcoded list.
- Update the `build` method to use `ref.watch(categoriesProvider)`.
- Implement a dynamic mapping for icons and colors (with defaults) for the dynamic categories.

#### [MODIFY] [search_screen.dart](file:///D:/violeafycrossapp/lib/features/search/presentation/search_screen.dart)
- Comment out/Remove the `_trending` hardcoded list.
- Remove the "Trending Searches" UI section.

#### [MODIFY] [shopping_repository.dart](file:///D:/violeafycrossapp/lib/repositories/shopping_repository.dart)
- Remove the fallback `['All']` from `getCategories` and `return []` if the backend returns nothing, allowing the UI to handle the empty state or add the 'All' option specifically when data exists.

## Verification Plan

### Automated Tests
- N/A (Manual verification on UI preferred for this task)

### Manual Verification
1. **Categories Screen**: Navigate to the categories screen. Verify that it now shows categories from the database. If the database is empty (after a purge), verify it shows an appropriate empty state (or just an empty grid).
2. **Search Screen**: Open the search screen. Verify that the "Trending Searches" section is no longer visible.
3. **Backend API**: Call `GET http://localhost:3000/api/categories`. Verify it returns an empty array `[]` if no products exist, instead of the previous hardcoded list.
4. **Populate Endpoint**: Verify that calling `POST http://localhost:3000/api/database/populate` no longer adds dummy data if the logic is commented out.
