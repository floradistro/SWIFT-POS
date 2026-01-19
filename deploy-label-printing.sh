#!/bin/bash
# Deploy Label Printing System - Complete Rewrite
# Run this to deploy all SQL migrations for optimized auto-print + AI label printing

set -e

echo "🏷️  Label Printing System Deployment"
echo "===================================="
echo ""
echo "This will deploy:"
echo "  1. get_order_for_printing RPC (optimized order fetch)"
echo "  2. get_orders_for_location RPC (order filters fix)"
echo "  3. print_labels tool (AI integration)"
echo ""
echo "Prerequisites:"
echo "  - Direct psql access OR"
echo "  - Supabase Dashboard SQL Editor access"
echo ""

# Database connection
DB_HOST="db.uaednwpxursknmwdeejn.supabase.co"
DB_PORT="5432"
DB_NAME="postgres"
DB_USER="postgres"
DB_PASS="holyfuckingshitfuck"

# Check if psql is available
if command -v psql &> /dev/null; then
    echo "✅ psql found, attempting direct deployment..."
    echo ""

    # Try to connect
    export PGPASSWORD="$DB_PASS"

    echo "📡 Testing connection..."
    if psql "host=$DB_HOST port=$DB_PORT user=$DB_USER dbname=$DB_NAME sslmode=require" -c "SELECT current_user, version();" &> /dev/null; then
        echo "✅ Connection successful!"
        echo ""

        echo "🚀 Deploying migrations..."

        # Deploy in order
        for migration in \
            "supabase/migrations/20260118_get_order_for_printing.sql" \
            "supabase/migrations/20260118_get_orders_for_location.sql" \
            "supabase/migrations/20260118_print_labels_tool.sql"
        do
            if [ -f "$migration" ]; then
                echo "  📄 $(basename $migration)"
                psql "host=$DB_HOST port=$DB_PORT user=$DB_USER dbname=$DB_NAME sslmode=require" -f "$migration" -q
                echo "     ✅ Success"
            else
                echo "     ⚠️  File not found: $migration"
            fi
        done

        echo ""
        echo "✅ All migrations deployed!"
        echo ""
        echo "Next steps:"
        echo "  1. Test auto-print with a sale"
        echo "  2. Ask AI to print labels"
        echo "  3. Check DEPLOYMENT_LABEL_PRINTING.md for details"

    else
        echo "❌ Connection failed (port 5432 blocked)"
        echo ""
        echo "📋 Manual deployment required:"
        echo ""
        echo "1. Go to: https://supabase.com/dashboard/project/uaednwpxursknmwdeejn/sql"
        echo ""
        echo "2. Copy/paste these files in order:"
        echo "   a. supabase/migrations/20260118_get_order_for_printing.sql"
        echo "   b. supabase/migrations/20260118_get_orders_for_location.sql"
        echo "   c. supabase/migrations/20260118_print_labels_tool.sql"
        echo ""
        echo "3. Run each one"
        echo ""
        echo "See DEPLOYMENT_LABEL_PRINTING.md for full instructions"
    fi
else
    echo "❌ psql not found"
    echo ""
    echo "📋 Manual deployment required:"
    echo ""
    echo "1. Go to: https://supabase.com/dashboard/project/uaednwpxursknmwdeejn/sql"
    echo ""
    echo "2. Copy/paste these files in order:"
    echo "   a. supabase/migrations/20260118_get_order_for_printing.sql"
    echo "   b. supabase/migrations/20260118_get_orders_for_location.sql"
    echo "   c. supabase/migrations/20260118_print_labels_tool.sql"
    echo ""
    echo "3. Run each one"
    echo ""
    echo "See DEPLOYMENT_LABEL_PRINTING.md for full instructions"
fi
